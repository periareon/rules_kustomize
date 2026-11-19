"""# Bazel rules for kustomize.

Equivalent to `defs.bzl`, retained for existing `load` statements.
"""

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

visibility("public")

KustomizationInfo = _KustomizationInfo
kustomization = _kustomization
kustomized_resources = _kustomized_resources
