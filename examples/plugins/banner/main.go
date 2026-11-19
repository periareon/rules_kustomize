// A kustomize exec generator plugin: emits a ConfigMap holding the
// `text` of its configuration object.
//
// kustomize invokes a legacy exec plugin with the path of its
// configuration object as the only argument and reads the generated
// resources from standard output.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "banner: expected the plugin configuration path as the first argument")
		os.Exit(1)
	}
	f, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "banner: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	name, text := "banner", ""
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if value, ok := strings.CutPrefix(line, "name:"); ok {
			name = strings.TrimSpace(value)
		}
		if value, ok := strings.CutPrefix(line, "text:"); ok {
			text = strings.TrimSpace(value)
		}
	}
	fmt.Printf("apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: %s\ndata:\n  banner: %s\n", name, text)
}
