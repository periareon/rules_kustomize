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
    ":kustomized_resources.bzl",
    _kustomized_resources = "kustomized_resources",
)

KustomizationInfo = _KustomizationInfo
kustomization = _kustomization
kustomized_resources = _kustomized_resources
