"""# kustomized_resources rule."""

load(
    "//kustomize/private:kustomized_resources.bzl",
    _kustomized_resources = "kustomized_resources",
)

kustomized_resources = _kustomized_resources
