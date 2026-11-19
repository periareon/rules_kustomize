"""# kustomization rule."""

load(
    "//kustomize/private:kustomization.bzl",
    _kustomization = "kustomization",
)

kustomization = _kustomization
