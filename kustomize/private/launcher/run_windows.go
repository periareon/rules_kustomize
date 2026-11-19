package main

import (
	"errors"
	"os"
	"os/exec"
	"os/signal"
)

// run starts kustomize as a child process and exits with its status.
func run(kustomize string, args []string) error {
	// The console delivers Ctrl+C to the whole process group; let
	// kustomize decide how to handle it and report its exit status.
	signal.Ignore(os.Interrupt)

	cmd := exec.Command(kustomize, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		os.Exit(exitErr.ExitCode())
	}
	return err
}
