load(
    "//kustomize/private/extensions:kustomize.bzl",
    _kustomize = "kustomize",
)

visibility("public")

kustomize = _kustomize
