"""Helpers for the golden file tests."""

load(
    "@bazel_skylib//rules:diff_test.bzl",
    "diff_test",
)
load(
    "//kustomize:defs.bzl",
    "kustomization",
    "kustomized_resources",
)

def kustomize_diff_test(
        name,
        golden_file,
        srcs = [],
        deps = [],
        kustomization_file = None,
        **kwargs):
    """Builds a kustomization and compares the result against a golden file.

    Args:
        name: The name of the kustomization, matching a directory below `testdata`.
        golden_file: The expected result.
        srcs: Files referenced by the kustomization.
        deps: Other kustomizations referenced by the kustomization.
        kustomization_file: The kustomization file, defaulting to `testdata/<name>/kustomization.yaml`.
        **kwargs: Additional arguments for `kustomized_resources`.
    """
    kustomization(
        name = name,
        deps = deps,
        src = kustomization_file or "testdata/%s/kustomization.yaml" % name,
        srcs = srcs,
    )

    generated_resources_file = name + "_resources.yaml"

    kustomized_resources(
        name = name + "_resources",
        kustomization = name,
        result = generated_resources_file,
        **kwargs
    )
    diff_test(
        name = name + "_test",
        file1 = generated_resources_file,
        file2 = golden_file,
        size = "small",
    )
