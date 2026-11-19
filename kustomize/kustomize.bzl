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
    ":kustomize_toolchain.bzl",
    _kustomize_toolchain = "kustomize_toolchain",
)
load(
    ":kustomized_resources.bzl",
    _kustomized_resources = "kustomized_resources",
)

visibility("public")

KustomizationInfo = _KustomizationInfo
kustomization = _kustomization
kustomize_toolchain = _kustomize_toolchain
kustomized_resources = _kustomized_resources
