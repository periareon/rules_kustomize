"""# Bazel rules for kustomize."""

load(
    ":kustomization.bzl",
    _kustomization = "kustomization",
)
load(
    ":kustomization_info.bzl",
    _KustomizationInfo = "KustomizationInfo",
)
load(
    ":kustomize_plugin.bzl",
    _kustomize_plugin = "kustomize_plugin",
)
load(
    ":kustomize_plugin_info.bzl",
    _KustomizePluginInfo = "KustomizePluginInfo",
)
load(
    ":kustomize_toolchain.bzl",
    _kustomize_toolchain = "kustomize_toolchain",
)
load(
    ":kustomized_resources.bzl",
    _kustomized_resources = "kustomized_resources",
)

KustomizationInfo = _KustomizationInfo
KustomizePluginInfo = _KustomizePluginInfo
kustomization = _kustomization
kustomize_plugin = _kustomize_plugin
kustomize_toolchain = _kustomize_toolchain
kustomized_resources = _kustomized_resources
