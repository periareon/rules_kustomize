// The builder behind the kustomized_resources rule.
//
// Bazel presents a kustomization's files spread over several roots: the
// source tree and the output tree(s) for generated files. kustomize
// expects to find everything within one directory tree, so the builder
// copies the files into a temporary directory laid out like Bazel's
// runfiles tree and runs "kustomize build" there. It reads the staged
// kustomization files to decide which of kustomize's gated features
// (Helm chart inflation, plugins) the build needs. Copying rather than
// symlinking keeps kustomize's default load restrictor satisfied, as it
// resolves symbolic links before checking that files sit below the
// kustomization root.
package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"strings"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "kustomize builder: %v\n", err)
		os.Exit(1)
	}
}

type options struct {
	kustomize     string
	helm          string
	manifest      string
	workspaceName string
	kustomization string
	output        string
	// kustomizeArgs are passed through to "kustomize build".
	kustomizeArgs []string
}

func parseArgs(argv []string) (*options, error) {
	opts := &options{}
	fs := flag.NewFlagSet("builder", flag.ContinueOnError)
	fs.StringVar(&opts.kustomize, "kustomize", "", "path to the kustomize binary")
	fs.StringVar(&opts.helm, "helm", "", "path to the helm binary, used when a kustomization inflates Helm charts")
	fs.StringVar(&opts.manifest, "manifest", "", "file listing the short path and the path of each input file on alternating lines")
	fs.StringVar(&opts.workspaceName, "workspace_name", "", "name of the main repository")
	fs.StringVar(&opts.kustomization, "kustomization", "", "short path of the kustomization file to build")
	fs.StringVar(&opts.output, "output", "", "file to write the built resources to")
	if err := fs.Parse(argv); err != nil {
		return nil, err
	}
	opts.kustomizeArgs = fs.Args()

	for name, value := range map[string]string{
		"kustomize":      opts.kustomize,
		"manifest":       opts.manifest,
		"workspace_name": opts.workspaceName,
		"kustomization":  opts.kustomization,
		"output":         opts.output,
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
		dst := filepath.Join(staging, filepath.FromSlash(stagedPath(opts.workspaceName, entry.shortPath)))
		if err := copyPath(entry.path, dst); err != nil {
			return fmt.Errorf("failed to stage %s: %w", entry.path, err)
		}
	}

	kustomize, err := filepath.Abs(opts.kustomize)
	if err != nil {
		return err
	}
	root := filepath.Join(staging, filepath.FromSlash(path.Dir(stagedPath(opts.workspaceName, opts.kustomization))))
	features, err := detectFeatures(staging)
	if err != nil {
		return err
	}

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
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("kustomize build failed: %w", err)
	}
	return output.Close()
}

// manifestEntry pairs an input file's short path, which determines
// where it is staged, with the path it can be read from.
type manifestEntry struct {
	shortPath string
	path      string
}

// readManifest parses a file written by Bazel in its "multiline" params
// file format: the short path and the path of each input file on
// alternating lines.
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
		shortPath := scanner.Text()
		if !scanner.Scan() {
			return nil, fmt.Errorf("manifest ends after short path %q without a matching path", shortPath)
		}
		entries = append(entries, manifestEntry{shortPath: shortPath, path: scanner.Text()})
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("failed to read manifest: %w", err)
	}
	return entries, nil
}

// stagedPath maps a file's short path to its location in the staging
// directory, mirroring Bazel's runfiles layout: files in the main
// repository sit below the workspace name, and files in other
// repositories below their repository's name.
func stagedPath(workspaceName, shortPath string) string {
	if rest, ok := strings.CutPrefix(shortPath, "../"); ok {
		return rest
	}
	return path.Join(workspaceName, shortPath)
}

// copyPath copies a file, or a directory tree, following symbolic
// links along the way.
func copyPath(src, dst string) error {
	info, err := os.Stat(src)
	if err != nil {
		return err
	}
	if info.IsDir() {
		children, err := os.ReadDir(src)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(dst, 0o755); err != nil {
			return err
		}
		for _, child := range children {
			if err := copyPath(filepath.Join(src, child.Name()), filepath.Join(dst, child.Name())); err != nil {
				return err
			}
		}
		return nil
	}
	return copyFile(src, dst, info.Mode().Perm())
}

func copyFile(src, dst string, mode os.FileMode) (err error) {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return err
	}
	defer func() {
		err = errors.Join(err, out.Close())
	}()
	_, err = io.Copy(out, in)
	return err
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
