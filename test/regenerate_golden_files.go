// Copies freshly built kustomization results over the golden files they
// are compared against.
//
// Run it with `bazel run //test:regenerate_golden_files`. Each argument
// pairs the rlocationpath of a built result with the workspace-relative
// path of its golden file, separated by "=". Bazel builds the results
// before this program runs, and `BUILD_WORKSPACE_DIRECTORY` points at
// the source tree to write into.
package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "regenerate_golden_files: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	workspace := os.Getenv("BUILD_WORKSPACE_DIRECTORY")
	if workspace == "" {
		return fmt.Errorf("BUILD_WORKSPACE_DIRECTORY is not set; invoke this program with `bazel run`")
	}

	for _, arg := range args {
		rlocationpath, golden, ok := strings.Cut(arg, "=")
		if !ok {
			return fmt.Errorf("argument %q is not of the form <rlocationpath>=<golden file>", arg)
		}

		result, err := runfiles.Rlocation(rlocationpath)
		if err != nil {
			return fmt.Errorf("failed to locate %s in runfiles: %w", rlocationpath, err)
		}
		content, err := os.ReadFile(result)
		if err != nil {
			return err
		}

		dst := filepath.Join(workspace, filepath.FromSlash(golden))
		existing, err := os.ReadFile(dst)
		if err == nil && bytes.Equal(existing, content) {
			continue
		}
		if err != nil && !os.IsNotExist(err) {
			return err
		}

		if err := os.WriteFile(dst, content, 0o644); err != nil {
			return err
		}
		fmt.Printf("Updated %s\n", golden)
	}
	return nil
}
