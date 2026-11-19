//go:build !windows

package main

import (
	"os"
	"syscall"
)

// run replaces the current process with kustomize.
func run(kustomize string, args []string) error {
	return syscall.Exec(kustomize, append([]string{kustomize}, args...), os.Environ())
}
