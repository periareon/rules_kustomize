// Assembles a kustomize plugin home directory for a toolchain.
//
// kustomize finds legacy plugins below $KUSTOMIZE_PLUGIN_HOME at
// <apiVersion>/<lowercased kind>/<Kind>. The rule works out that path
// for each plugin file; this program copies the files into place.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/UebelAndre/rules_kustomize/kustomize/private/fscopy"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "plugin_home: %v\n", err)
		os.Exit(1)
	}
}

func run(argv []string) error {
	fs := flag.NewFlagSet("plugin_home", flag.ContinueOnError)
	manifest := fs.String("manifest", "", "file listing the path below the plugin home and the source path of each file on alternating lines")
	output := fs.String("output", "", "the plugin home directory to create")
	base := fs.String("base", "", "a plugin home directory whose content is copied in first")
	if err := fs.Parse(argv); err != nil {
		return err
	}
	if *manifest == "" || *output == "" {
		return fmt.Errorf("the --manifest and --output flags are required")
	}

	if err := os.MkdirAll(*output, 0o755); err != nil {
		return err
	}
	if *base != "" {
		if err := fscopy.CopyPath(*base, *output); err != nil {
			return fmt.Errorf("failed to copy the base plugin home: %w", err)
		}
	}
	prefix := *output + string(filepath.Separator)

	f, err := os.Open(*manifest)
	if err != nil {
		return err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		rel := scanner.Text()
		if !scanner.Scan() {
			return fmt.Errorf("manifest ends after %q without a source path", rel)
		}
		dst := filepath.Join(*output, filepath.FromSlash(rel))
		if !strings.HasPrefix(dst, prefix) {
			return fmt.Errorf("refusing to place %s outside of the plugin home", rel)
		}
		if err := fscopy.CopyPath(scanner.Text(), dst); err != nil {
			return err
		}
	}
	return scanner.Err()
}
