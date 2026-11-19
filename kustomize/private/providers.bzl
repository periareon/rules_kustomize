"""Providers shared by the kustomize rules."""

visibility("//kustomize/...")

KustomizationInfo = provider(
    doc = "Kustomization root summary",
    fields = {
        "target_file": "File: The top-level kustomization file defining this kustomization.",
        "transitive_resources": "Depset[File]: The set of files (including other kustomizations) referenced by this kustomization.",
    },
)
