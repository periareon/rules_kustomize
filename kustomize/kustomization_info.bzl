"""# KustomizationInfo provider."""

load(
    "//kustomize/private:providers.bzl",
    _KustomizationInfo = "KustomizationInfo",
)

KustomizationInfo = _KustomizationInfo
