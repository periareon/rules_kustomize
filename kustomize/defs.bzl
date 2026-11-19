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
    ":kustomize_toolchain.bzl",
    _kustomize_toolchain = "kustomize_toolchain",
)
load(
    ":kustomized_resources.bzl",
    _kustomized_resources = "kustomized_resources",
)

KustomizationInfo = _KustomizationInfo
kustomization = _kustomization
kustomize_toolchain = _kustomize_toolchain
kustomized_resources = _kustomized_resources
