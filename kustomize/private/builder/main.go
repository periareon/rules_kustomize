// The builder behind the kustomized_resources rule.
//
// Bazel presents a kustomization's files spread over several roots: the
// source tree and the output tree(s) for generated files. kustomize
// expects to find everything within one directory tree, so the builder
// copies the files into a temporary directory, at the locations the rule
// worked out for them, and runs "kustomize build" there. It reads the
// staged kustomization files to decide which of kustomize's gated
// features (Helm chart inflation, plugins) the build needs. Copying rather than
// symlinking keeps kustomize's default load restrictor satisfied, as it
// resolves symbolic links before checking that files sit below the
// kustomization root.
package main

import (
	"archive/tar"
	"bufio"
	"compress/gzip"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/UebelAndre/rules_kustomize/kustomize/private/fscopy"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "kustomize builder: %v\n", err)
		os.Exit(1)
	}
}

// pluginEntry places a file below the plugin home.
type pluginEntry struct {
	rel  string
	path string
}

// pluginEntries parses repeated "--plugin <rel>=<path>" flags.
type pluginEntries []pluginEntry

func (p *pluginEntries) String() string { return fmt.Sprint(*p) }

func (p *pluginEntries) Set(value string) error {
	rel, path, ok := strings.Cut(value, "=")
	if !ok || rel == "" || path == "" {
		return fmt.Errorf("plugin entry %q is not of the form <path below plugin home>=<source path>", value)
	}
	*p = append(*p, pluginEntry{rel: rel, path: path})
	return nil
}

type options struct {
	kustomize  string
	helm       string
	manifest   string
	root       string
	output     string
	pluginHome string
	plugins    pluginEntries
	// kustomizeArgs are passed through to "kustomize build".
	kustomizeArgs []string
}

func parseArgs(argv []string) (*options, error) {
	opts := &options{}
	fs := flag.NewFlagSet("builder", flag.ContinueOnError)
	fs.StringVar(&opts.kustomize, "kustomize", "", "path to the kustomize binary")
	fs.StringVar(&opts.helm, "helm", "", "path to the helm binary, used when a kustomization inflates Helm charts")
	fs.StringVar(&opts.manifest, "manifest", "", "file listing an operation (copy or extract), the staged path and the source path of each input file on consecutive lines")
	fs.StringVar(&opts.root, "root", "", "staged path of the directory holding the kustomization file to build")
	fs.StringVar(&opts.output, "output", "", "file to write the built resources to")
	fs.StringVar(&opts.pluginHome, "plugin_home", "", "a toolchain's plugin home directory to make available to kustomize")
	fs.Var(&opts.plugins, "plugin", "a file to place below the plugin home, as <path below plugin home>=<source path>; may repeat")
	if err := fs.Parse(argv); err != nil {
		return nil, err
	}
	opts.kustomizeArgs = fs.Args()

	for name, value := range map[string]string{
		"kustomize": opts.kustomize,
		"manifest":  opts.manifest,
		"root":      opts.root,
		"output":    opts.output,
	} {
		if value == "" {
			return nil, fmt.Errorf("the --%s flag is required", name)
		}
	}
	return opts, nil
}

func run(argv []string) error {
	opts, err := parseArgs(argv)
	if err != nil {
		return err
	}

	entries, err := readManifest(opts.manifest)
	if err != nil {
		return err
	}

	staging, err := os.MkdirTemp("", "kustomize-build-")
	if err != nil {
		return fmt.Errorf("failed to create staging directory: %w", err)
	}
	defer os.RemoveAll(staging)

	// Resolve the staging directory the same way kustomize resolves the
	// files beneath it (notably on macOS, where the temporary directory
	// sits behind a symbolic link).
	if staging, err = filepath.EvalSymlinks(staging); err != nil {
		return fmt.Errorf("failed to resolve staging directory: %w", err)
	}

	for _, entry := range entries {
		dst := filepath.Join(staging, filepath.FromSlash(entry.stagedPath))
		if !strings.HasPrefix(dst, staging+string(filepath.Separator)) {
			return fmt.Errorf("refusing to stage %s outside of the staging directory", entry.stagedPath)
		}
		var err error
		switch entry.op {
		case opCopy:
			err = fscopy.CopyPath(entry.path, dst)
		case opExtract:
			err = extractTarGz(entry.path, dst)
		}
		if err != nil {
			return fmt.Errorf("failed to stage %s: %w", entry.path, err)
		}
	}

	pluginHome, err := stagePlugins(staging, opts.pluginHome, opts.plugins)
	if err != nil {
		return err
	}

	kustomize, err := filepath.Abs(opts.kustomize)
	if err != nil {
		return err
	}
	features, err := detectFeatures(staging)
	if err != nil {
		return err
	}

	root := filepath.Join(staging, filepath.FromSlash(opts.root))
	args := []string{"build", root}
	if features.helm {
		if opts.helm == "" {
			return errors.New("the kustomization inflates Helm charts, but no Helm toolchain is available")
		}
		// kustomize invokes helm from its own working directory, so
		// the path must not depend on ours.
		helm, err := filepath.Abs(opts.helm)
		if err != nil {
			return err
		}
		args = append(args, "--enable-helm", "--helm-command", helm)
	}
	if features.plugins {
		args = append(args, "--enable-alpha-plugins", "--enable-exec")
	}
	args = append(args, opts.kustomizeArgs...)

	output, err := os.Create(opts.output)
	if err != nil {
		return fmt.Errorf("failed to create output file: %w", err)
	}
	defer output.Close()

	cmd := exec.Command(kustomize, args...)
	cmd.Stdout = output
	cmd.Stderr = os.Stderr
	if pluginHome != "" {
		cmd.Env = append(os.Environ(), "KUSTOMIZE_PLUGIN_HOME="+pluginHome)
	}
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("kustomize build failed: %w", err)
	}
	return output.Close()
}

// The operations that stage an input file.
const (
	// opCopy copies the file to the staged path.
	opCopy = "copy"
	// opExtract unpacks the file, a gzip compressed tar archive, into the
	// staged path, which names a directory.
	opExtract = "extract"
)

// manifestEntry describes how an input file is staged: the operation,
// the path it is staged at relative to the staging directory, and the
// path it can be read from.
type manifestEntry struct {
	op         string
	stagedPath string
	path       string
}

// readManifest parses a file written by Bazel in its "multiline" params
// file format: the operation, the staged path and the source path of
// each input file on consecutive lines.
func readManifest(name string) ([]manifestEntry, error) {
	f, err := os.Open(name)
	if err != nil {
		return nil, fmt.Errorf("failed to open manifest: %w", err)
	}
	defer f.Close()
	return parseManifest(f)
}

func parseManifest(r io.Reader) ([]manifestEntry, error) {
	var entries []manifestEntry
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		op := scanner.Text()
		if op != opCopy && op != opExtract {
			return nil, fmt.Errorf("unknown staging operation %q in manifest", op)
		}
		if !scanner.Scan() {
			return nil, fmt.Errorf("manifest ends after operation %q without a staged path", op)
		}
		stagedPath := scanner.Text()
		if !scanner.Scan() {
			return nil, fmt.Errorf("manifest ends after staged path %q without a matching source path", stagedPath)
		}
		entries = append(entries, manifestEntry{op: op, stagedPath: stagedPath, path: scanner.Text()})
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("failed to read manifest: %w", err)
	}
	return entries, nil
}

// extractTarGz unpacks a gzip compressed tar archive, such as a packaged
// Helm chart, into the directory dir.
func extractTarGz(src, dir string) error {
	f, err := os.Open(src)
	if err != nil {
		return err
	}
	defer f.Close()

	// Helm writes a custom gzip header; Go's reader tolerates it where
	// some other extractors don't.
	gz, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	defer gz.Close()

	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	prefix := dir + string(filepath.Separator)

	tr := tar.NewReader(gz)
	for {
		header, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}

		dst := filepath.Join(dir, filepath.FromSlash(header.Name))
		if !strings.HasPrefix(dst, prefix) {
			return fmt.Errorf("archive entry %q escapes its destination directory", header.Name)
		}

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(dst, 0o755); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
				return err
			}
			out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, os.FileMode(header.Mode).Perm())
			if errors.Is(err, os.ErrExist) {
				return fmt.Errorf("%s is staged from more than one input", dst)
			}
			if err != nil {
				return err
			}
			_, err = io.Copy(out, tr)
			if err := errors.Join(err, out.Close()); err != nil {
				return err
			}
		default:
			return fmt.Errorf("archive entry %q has unsupported type %q", header.Name, header.Typeflag)
		}
	}
}

// features records which of kustomize's gated features a build needs.
type features struct {
	// helm is set when a kustomization uses the Helm chart inflator.
	helm bool
	// plugins is set when a kustomization lists plugins, which covers
	// legacy plugins as well as exec functions.
	plugins bool
}

// kustomizationFileNames are the names kustomize recognizes for a
// kustomization file.
var kustomizationFileNames = map[string]bool{
	"kustomization.yaml": true,
	"kustomization.yml":  true,
	"kustomization":      true,
}

// Top-level fields of a kustomization file that call for a gated feature.
var (
	helmFields   = regexp.MustCompile(`^(helmCharts|helmGlobals)\s*:`)
	pluginFields = regexp.MustCompile(`^(generators|transformers|validators)\s*:`)
)

// detectFeatures scans every kustomization file below dir for the
// top-level fields that need a gated feature. Bases and components are
// staged below the same directory, so their needs are found too.
func detectFeatures(dir string) (features, error) {
	var found features
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !kustomizationFileNames[d.Name()] {
			return err
		}
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()
		scanner := bufio.NewScanner(f)
		scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
		for scanner.Scan() {
			line := scanner.Text()
			if helmFields.MatchString(line) {
				found.helm = true
			}
			if pluginFields.MatchString(line) {
				found.plugins = true
			}
		}
		return scanner.Err()
	})
	return found, err
}

// stagePlugins assembles the plugin home kustomize should use: the
// toolchain's plugin home, if any, with the target's own plugins laid
// over it. It returns "" when there is nothing to offer.
func stagePlugins(staging, toolchainHome string, plugins []pluginEntry) (string, error) {
	if toolchainHome == "" && len(plugins) == 0 {
		return "", nil
	}
	home := filepath.Join(staging, "kustomize-plugins")
	if err := os.MkdirAll(home, 0o755); err != nil {
		return "", err
	}
	if toolchainHome != "" {
		if err := fscopy.CopyPath(toolchainHome, home); err != nil {
			return "", fmt.Errorf("failed to stage the toolchain's plugins: %w", err)
		}
	}
	prefix := home + string(filepath.Separator)
	for _, plugin := range plugins {
		dst := filepath.Join(home, filepath.FromSlash(plugin.rel))
		if !strings.HasPrefix(dst, prefix) {
			return "", fmt.Errorf("refusing to place plugin file %s outside of the plugin home", plugin.rel)
		}
		if err := fscopy.CopyPath(plugin.path, dst); err != nil {
			return "", fmt.Errorf("failed to stage plugin file %s: %w", plugin.path, err)
		}
	}
	return home, nil
}
