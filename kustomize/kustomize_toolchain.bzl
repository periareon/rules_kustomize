"""# kustomize_toolchain rule."""

load(
    "//kustomize/private:toolchain.bzl",
    _kustomize_toolchain = "kustomize_toolchain",
)

kustomize_toolchain = _kustomize_toolchain
