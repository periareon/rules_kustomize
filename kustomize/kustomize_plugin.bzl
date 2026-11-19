"""# kustomize_plugin rule."""

load(
    "//kustomize/private:plugin.bzl",
    _kustomize_plugin = "kustomize_plugin",
)

kustomize_plugin = _kustomize_plugin
