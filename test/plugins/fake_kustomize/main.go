// Stands in for kustomize behind a launcher in the tests: prints the
// files below $KUSTOMIZE_PLUGIN_HOME, so the test can see which plugins
// the launcher made available.
package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
)

func main() {
	home := os.Getenv("KUSTOMIZE_PLUGIN_HOME")
	if home == "" {
		fmt.Println("KUSTOMIZE_PLUGIN_HOME is not set")
		return
	}
	var files []string
	err := filepath.WalkDir(home, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		rel, err := filepath.Rel(home, path)
		if err != nil {
			return err
		}
		files = append(files, filepath.ToSlash(rel))
		return nil
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "fake kustomize: %v\n", err)
		os.Exit(1)
	}
	sort.Strings(files)
	for _, file := range files {
		fmt.Println(file)
	}
}
