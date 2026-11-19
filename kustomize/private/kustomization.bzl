"""The `kustomization` rule."""

load(":providers.bzl", "KustomizationInfo")

visibility("//kustomize/...")

# The file names kustomize recognizes as a kustomization.
_KUSTOMIZATION_FILE_NAMES = ["kustomization.yaml", "kustomization.yml", "kustomization"]

def _kustomization_impl(ctx):
    file = ctx.file.src
    if file.basename not in _KUSTOMIZATION_FILE_NAMES:
        fail("{} is not a kustomization file; kustomize only recognizes {}".format(
            file.short_path,
            ", ".join(_KUSTOMIZATION_FILE_NAMES),
        ))
    deps = [dep[KustomizationInfo] for dep in ctx.attr.deps]

    transitive_resources = depset(
        direct = [ctx.file.src] + ctx.files.srcs,
        transitive = [dep.transitive_resources for dep in deps],
    )

    return [
        # The kustomization file is the target's output, so that other
        # targets can name it in `data` and look it up through
        # `$(rlocationpath)`; everything it references rides along as
        # runfiles.
        DefaultInfo(
            files = depset([ctx.file.src]),
            runfiles = ctx.runfiles(transitive_files = transitive_resources),
        ),
        KustomizationInfo(
            target_file = ctx.file.src,
            transitive_resources = transitive_resources,
        ),
    ]

kustomization = rule(
    doc = """Defines a kustomization from a set of source files and other kustomizations.

Build it with `kustomized_resources`, which enables kustomize's Helm and
plugin features by itself when a kustomization file in the tree uses
them. The target's own output is its kustomization file, and its
runfiles hold everything the kustomization references, so tests and
tools that read the sources can depend on it directly.""",
    implementation = _kustomization_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "The set of kustomizations referenced as resources by this kustomization.",
            providers = [KustomizationInfo],
        ),
        "src": attr.label(
            doc = "kustomization.yaml, kustomization.yml, or kustomization file for this kustomization. Must carry one of those names.",
            allow_single_file = True,
            mandatory = True,
        ),
        "srcs": attr.label_list(
            doc = "Files referenced as resources for this kustomization.",
            allow_files = True,
        ),
    },
    provides = [KustomizationInfo],
)
