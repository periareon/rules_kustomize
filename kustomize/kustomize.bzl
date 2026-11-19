"""Rules for building kustomizations with kustomize."""

load(
    "//kustomize/private:kustomization.bzl",
    _kustomization = "kustomization",
)
load(
    "//kustomize/private:kustomized_resources.bzl",
    _kustomized_resources = "kustomized_resources",
)
load(
    "//kustomize/private:providers.bzl",
    _KustomizationInfo = "KustomizationInfo",
)

visibility("public")

KustomizationInfo = _KustomizationInfo
kustomization = _kustomization
kustomized_resources = _kustomized_resources
