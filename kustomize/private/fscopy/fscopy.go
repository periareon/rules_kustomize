// Package fscopy copies files and directory trees the way the kustomize
// rules stage their inputs: following symbolic links, preserving
// permission bits, and refusing to write a destination twice.
package fscopy

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// CopyPath copies a file, or a directory tree, following symbolic links
// along the way. Directories are merged into an existing destination;
// a file that already exists at its destination is an error, as it
// means two inputs claim the same place.
func CopyPath(src, dst string) error {
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
			if err := CopyPath(filepath.Join(src, child.Name()), filepath.Join(dst, child.Name())); err != nil {
				return err
			}
		}
		return nil
	}
	return CopyFile(src, dst, info.Mode().Perm())
}

// CopyFile copies a regular file to dst with the given permission bits,
// creating parent directories as needed.
func CopyFile(src, dst string, mode os.FileMode) (err error) {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if errors.Is(err, os.ErrExist) {
		return fmt.Errorf("%s is staged from more than one input", dst)
	}
	if err != nil {
		return err
	}
	defer func() {
		err = errors.Join(err, out.Close())
	}()
	_, err = io.Copy(out, in)
	return err
}
