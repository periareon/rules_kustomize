// The `bazel run` launcher for kustomize.
//
// It locates kustomize through runfiles, changes to the directory `bazel
// run` was invoked from (`BUILD_WORKING_DIRECTORY`) and hands over to
// kustomize, so relative paths in arguments such as `build ./overlay`
// resolve the way they would for a locally installed kustomize.
// Arguments, environment and exit status pass through unchanged.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

// kustomizeRlocationpath is the rlocationpath of the kustomize binary.
// It is set at link time from the toolchain's `KUSTOMIZE_RLOCATIONPATH`
// make variable.
var kustomizeRlocationpath string

// pluginHomeRlocationpath is the rlocationpath of the toolchain's plugin
// home directory, set at link time from its
// `KUSTOMIZE_PLUGIN_HOME_RLOCATIONPATH` make variable. It may be empty.
var pluginHomeRlocationpath string

func main() {
	if kustomizeRlocationpath == "" {
		fatalf("launcher was built without the rlocationpath of kustomize")
	}

	kustomize, err := runfiles.Rlocation(kustomizeRlocationpath)
	if err != nil {
		fatalf("failed to locate %s in runfiles: %v", kustomizeRlocationpath, err)
	}

	// Resolve before changing directory in case the runfiles path is relative.
	kustomize, err = filepath.Abs(kustomize)
	if err != nil {
		fatalf("failed to resolve %s: %v", kustomize, err)
	}

	if pluginHomeRlocationpath != "" {
		pluginHome, err := runfiles.Rlocation(pluginHomeRlocationpath)
		if err != nil {
			fatalf("failed to locate %s in runfiles: %v", pluginHomeRlocationpath, err)
		}
		if pluginHome, err = filepath.Abs(pluginHome); err != nil {
			fatalf("failed to resolve %s: %v", pluginHome, err)
		}
		// An explicit setting from the caller wins.
		if _, set := os.LookupEnv("KUSTOMIZE_PLUGIN_HOME"); !set {
			os.Setenv("KUSTOMIZE_PLUGIN_HOME", pluginHome)
		}
	}

	if dir := os.Getenv("BUILD_WORKING_DIRECTORY"); dir != "" {
		if err := os.Chdir(dir); err != nil {
			fatalf("failed to change to BUILD_WORKING_DIRECTORY: %v", err)
		}
	}

	if err := run(kustomize, os.Args[1:]); err != nil {
		fatalf("failed to run %s: %v", kustomize, err)
	}
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "kustomize launcher: "+format+"\n", args...)
	os.Exit(1)
}
