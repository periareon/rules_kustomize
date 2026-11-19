// A KRM exec generator function used by the tests.
//
// kustomize runs an exec function with a ResourceList on standard input,
// whose functionConfig is the configuration object that named the
// function, and reads a ResourceList back from standard output. This one
// ignores the input items and emits a ConfigMap carrying the
// functionConfig's `message`, uppercased.
package main

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
)

var message = regexp.MustCompile(`(?m)^\s*message:\s*(\S+)`)

func main() {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		fmt.Fprintf(os.Stderr, "shouter: %v\n", err)
		os.Exit(1)
	}
	match := message.FindSubmatch(input)
	if match == nil {
		fmt.Fprintln(os.Stderr, "shouter: the function configuration has no `message` field")
		os.Exit(1)
	}
	fmt.Printf(`apiVersion: config.kubernetes.io/v1
kind: ResourceList
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: shouter
  data:
    message: %s
`, strings.ToUpper(string(match[1])))
}
