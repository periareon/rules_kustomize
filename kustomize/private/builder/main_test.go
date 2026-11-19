package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParseManifest(t *testing.T) {
	got, err := parseManifest(strings.NewReader("copy\nws/a/b.yaml\nbazel-out/bin/a/b.yaml\nextract\nws/a/charts\nexternal/r/c.tgz\n"))
	if err != nil {
		t.Fatal(err)
	}
	want := []manifestEntry{
		{op: opCopy, stagedPath: "ws/a/b.yaml", path: "bazel-out/bin/a/b.yaml"},
		{op: opExtract, stagedPath: "ws/a/charts", path: "external/r/c.tgz"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("parseManifest = %v, want %v", got, want)
	}

	if _, err := parseManifest(strings.NewReader("copy\na/b.yaml\n")); err == nil {
		t.Error("expected an error for a truncated manifest")
	}
	if _, err := parseManifest(strings.NewReader("move\na/b.yaml\nc\n")); err == nil {
		t.Error("expected an error for an unknown operation")
	}
}

func TestParseArgsPassesThroughKustomizeArgs(t *testing.T) {
	opts, err := parseArgs([]string{
		"--manifest=m", "--kustomize", "k", "--root", "ws/a", "--output", "o",
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

func writeTarGz(t *testing.T, path string, files map[string]string) {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	// Mimic the header Helm writes when packaging a chart.
	gz.Extra = []byte{'+', 'a', 'H', 'R', '0', 'c', 'H', 'M', '6', 'L', 'y', '9', 'o', 'Z', 'W', 'x', 't', 'L', 'n', 'N', 'o', 'L', 'w'}
	tw := tar.NewWriter(gz)
	for name, content := range files {
		if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o644, Size: int64(len(content)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestExtractTarGz(t *testing.T) {
	archive := filepath.Join(t.TempDir(), "chart.tgz")
	writeTarGz(t, archive, map[string]string{
		"greeter/Chart.yaml":               "name: greeter\n",
		"greeter/templates/configmap.yaml": "kind: ConfigMap\n",
	})
	dir := filepath.Join(t.TempDir(), "charts")

	if err := extractTarGz(archive, dir); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(dir, "greeter", "templates", "configmap.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "kind: ConfigMap\n" {
		t.Errorf("extracted content = %q", got)
	}
}

func TestExtractTarGzRejectsEscapingEntries(t *testing.T) {
	archive := filepath.Join(t.TempDir(), "evil.tgz")
	writeTarGz(t, archive, map[string]string{"../escaped.yaml": "kind: Secret\n"})

	if err := extractTarGz(archive, filepath.Join(t.TempDir(), "charts")); err == nil {
		t.Error("expected an error for an entry escaping the destination directory")
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
