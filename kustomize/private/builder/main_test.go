package main

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestStagedPath(t *testing.T) {
	cases := []struct {
		shortPath string
		want      string
	}{
		{"app/kustomization.yaml", "ws/app/kustomization.yaml"},
		{"../other_repo/charts/Chart.yaml", "other_repo/charts/Chart.yaml"},
	}
	for _, c := range cases {
		if got := stagedPath("ws", c.shortPath); got != c.want {
			t.Errorf("stagedPath(%q) = %q, want %q", c.shortPath, got, c.want)
		}
	}
}

func TestParseManifest(t *testing.T) {
	got, err := parseManifest(strings.NewReader("a/b.yaml\nbazel-out/bin/a/b.yaml\n../r/c.yaml\nexternal/r/c.yaml\n"))
	if err != nil {
		t.Fatal(err)
	}
	want := []manifestEntry{
		{shortPath: "a/b.yaml", path: "bazel-out/bin/a/b.yaml"},
		{shortPath: "../r/c.yaml", path: "external/r/c.yaml"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("parseManifest = %v, want %v", got, want)
	}

	if _, err := parseManifest(strings.NewReader("a/b.yaml\n")); err == nil {
		t.Error("expected an error for a manifest with an odd number of lines")
	}
}

func TestParseArgsPassesThroughKustomizeArgs(t *testing.T) {
	opts, err := parseArgs([]string{
		"--manifest=m", "--kustomize", "k", "--workspace_name", "ws", "--kustomization", "a/kustomization.yaml", "--output", "o",
		"--", "--enable-alpha-plugins", "--env", "A=b",
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"--enable-alpha-plugins", "--env", "A=b"}
	if !reflect.DeepEqual(opts.kustomizeArgs, want) {
		t.Errorf("kustomizeArgs = %v, want %v", opts.kustomizeArgs, want)
	}

	if _, err := parseArgs([]string{"--kustomize", "k"}); err == nil {
		t.Error("expected an error for missing required flags")
	}
}

func TestCopyPath(t *testing.T) {
	src := t.TempDir()
	dst := filepath.Join(t.TempDir(), "staged")
	if err := os.MkdirAll(filepath.Join(src, "charts", "templates"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(src, "charts", "templates", "svc.yaml"), []byte("kind: Service\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := copyPath(src, dst); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(dst, "charts", "templates", "svc.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "kind: Service\n" {
		t.Errorf("copied content = %q", got)
	}
}

func TestDetectFeatures(t *testing.T) {
	dir := t.TempDir()
	write := func(rel, content string) {
		t.Helper()
		path := filepath.Join(dir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	write("app/kustomization.yaml", "resources:\n- ../base\n")
	got, err := detectFeatures(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != (features{}) {
		t.Errorf("plain kustomization detected as %+v", got)
	}

	// A base below the root counts, a nested key or an unrelated file does not.
	write("base/kustomization", "helmCharts:\n- name: x\n")
	write("app/values.yaml", "generators:\n- nope\n")
	write("app/deployment.yaml", "spec:\n  transformers: []\n")
	got, err = detectFeatures(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != (features{helm: true}) {
		t.Errorf("helm base detected as %+v", got)
	}

	write("app/kustomization.yaml", "transformers:\n- plugin.yaml\n")
	got, err = detectFeatures(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != (features{helm: true, plugins: true}) {
		t.Errorf("plugins detected as %+v", got)
	}
}
