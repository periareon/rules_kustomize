"""# KustomizePluginInfo provider."""

load(
    "//kustomize/private:plugin.bzl",
    _KustomizePluginInfo = "KustomizePluginInfo",
)

KustomizePluginInfo = _KustomizePluginInfo
