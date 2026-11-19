// A kustomize exec generator plugin used by the tests.
//
// kustomize invokes a legacy exec plugin with the path of its config
// file as the only argument and reads the generated resources from
// standard output. This one emits a ConfigMap carrying the `message`
// field of its config.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "greeter: expected the plugin config path as the first argument")
		os.Exit(1)
	}
	f, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "greeter: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	name, message := "greeter", ""
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if value, ok := strings.CutPrefix(line, "name:"); ok {
			name = strings.TrimSpace(value)
		}
		if value, ok := strings.CutPrefix(line, "message:"); ok {
			message = strings.TrimSpace(value)
		}
	}
	fmt.Printf("apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: %s\ndata:\n  message: %s\n", name, message)
}
