package fscopy

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCopyPath(t *testing.T) {
	src := t.TempDir()
	dst := filepath.Join(t.TempDir(), "staged")
	if err := os.MkdirAll(filepath.Join(src, "charts", "templates"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(src, "charts", "templates", "svc.yaml"), []byte("kind: Service\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(src, "plugin"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	if err := CopyPath(src, dst); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(dst, "charts", "templates", "svc.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "kind: Service\n" {
		t.Errorf("copied content = %q", got)
	}
	info, err := os.Stat(filepath.Join(dst, "plugin"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm()&0o100 == 0 {
		t.Errorf("executable bit not preserved: %v", info.Mode())
	}

	if err := CopyPath(filepath.Join(src, "plugin"), filepath.Join(dst, "plugin")); err == nil {
		t.Error("expected an error when a destination is written twice")
	}
}
