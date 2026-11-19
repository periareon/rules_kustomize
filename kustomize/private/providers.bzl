"""Providers shared by the kustomize rules."""

visibility("//kustomize/...")

KustomizationInfo = provider(
    doc = "Kustomization root summary",
    fields = {
        "include_prefix": "str: The directory below a depending kustomization's root at which this kustomization is placed, or empty to keep its own location.",
        "target_file": "File: The top-level kustomization file defining this kustomization.",
        "transitive_layout": "Depset[struct]: Where every file referenced by this kustomization sits when it is built, as `struct(file = File, path = str, extract = bool)` entries: the file, its path relative to the staging root, and whether it is an archive to unpack there rather than a file to copy.",
        "transitive_resources": "Depset[File]: The set of files (including other kustomizations) referenced by this kustomization.",
    },
)
