"""The `kustomization` rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":layout.bzl", "relative_path", "staged_path")
load(":providers.bzl", "KustomizationInfo")

visibility("//kustomize/...")

def _prefixed_layout(ctx, root, info):
    """Place a dependency below this kustomization's root, at its `include_prefix`.

    The dependency's whole layout moves along, so its own bases keep their
    positions relative to it.
    """
    prefix_dir = paths.normalize(paths.join(root, info.include_prefix))
    base = paths.dirname(staged_path(info.target_file, ctx.workspace_name))
    layout = []
    for entry in info.transitive_layout.to_list():
        path = paths.normalize(paths.join(prefix_dir, relative_path(entry.path, base)))
        if path.startswith("../"):
            fail("{} placed at \"{}\" puts {} outside of the staging tree".format(info.target_file.owner, info.include_prefix, entry.file.short_path))
        layout.append(struct(file = entry.file, path = path, extract = entry.extract))
    return layout

def _include_prefix(ctx):
    """Validate and normalize this kustomization's `include_prefix`."""
    prefix = ctx.attr.include_prefix
    if not prefix:
        return ""
    if paths.is_absolute(prefix):
        fail("include_prefix \"{}\" for {} must be a relative path".format(prefix, ctx.label))
    prefix = paths.normalize(prefix)
    if prefix in ("", ".") or prefix.startswith("../"):
        fail("include_prefix \"{}\" for {} must name a directory below the depending kustomization's root".format(ctx.attr.include_prefix, ctx.label))
    return prefix

def _chart_layout(ctx, root):
    """Unpack each packaged chart below the kustomization's `chart_home`."""
    chart_home = ctx.attr.chart_home
    if paths.is_absolute(chart_home):
        fail("chart_home \"{}\" must be a relative path".format(chart_home))
    chart_dir = paths.normalize(paths.join(root, chart_home))
    if chart_dir != root and not chart_dir.startswith(root + "/"):
        fail("chart_home \"{}\" escapes the kustomization root".format(chart_home))

    return [struct(file = f, path = chart_dir, extract = True) for f in ctx.files.helm_charts]

# The file names kustomize recognizes as a kustomization.
_KUSTOMIZATION_FILE_NAMES = ["kustomization.yaml", "kustomization.yml", "kustomization"]

def _kustomization_impl(ctx):
    workspace_name = ctx.workspace_name
    file = ctx.file.src
    if file.basename not in _KUSTOMIZATION_FILE_NAMES:
        fail("{} is not a kustomization file; kustomize only recognizes {}".format(
            file.short_path,
            ", ".join(_KUSTOMIZATION_FILE_NAMES),
        ))
    root = paths.dirname(staged_path(file, workspace_name))

    direct_files = [file] + ctx.files.srcs + ctx.files.helm_charts
    direct_layout = [struct(file = f, path = staged_path(f, workspace_name), extract = False) for f in [file] + ctx.files.srcs]
    transitive_files = []
    transitive_layout = []

    # A dependency declaring an `include_prefix` is placed below this
    # root; any other keeps its own location, as `../base` expects.
    prefixes = {}
    for dep in ctx.attr.deps:
        info = dep[KustomizationInfo]
        transitive_files.append(info.transitive_resources)
        if not info.include_prefix:
            transitive_layout.append(info.transitive_layout)
            continue
        if info.include_prefix in prefixes:
            fail("deps {} and {} of {} both use the include_prefix \"{}\"".format(
                prefixes[info.include_prefix],
                dep.label,
                ctx.label,
                info.include_prefix,
            ))
        prefixes[info.include_prefix] = dep.label
        direct_layout.extend(_prefixed_layout(ctx, root, info))

    direct_layout.extend(_chart_layout(ctx, root))

    transitive_resources = depset(direct_files, transitive = transitive_files)

    return [
        # The kustomization file is the target's output, so that other
        # targets can name it in `data` and look it up through
        # `$(rlocationpath)`; everything it references rides along as
        # runfiles.
        DefaultInfo(
            files = depset([file]),
            runfiles = ctx.runfiles(transitive_files = transitive_resources),
        ),
        KustomizationInfo(
            include_prefix = _include_prefix(ctx),
            target_file = file,
            transitive_layout = depset(direct_layout, transitive = transitive_layout),
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
        "chart_home": attr.string(
            doc = """The directory below the kustomization root into which `helm_charts` are unpacked.

Must agree with the `helmGlobals.chartHome` field, whose default this matches.""",
            default = "charts",
        ),
        "deps": attr.label_list(
            doc = "The set of kustomizations referenced as resources by this kustomization.",
            providers = [KustomizationInfo],
        ),
        "helm_charts": attr.label_list(
            doc = """Packaged Helm charts (`.tgz` archives) for the `helmCharts` field to inflate.

Each archive is unpacked below `chart_home` before building, where
kustomize finds the chart by name and doesn't attempt to download it.
Archives may come from `rules_helm`, whether a chart it packages or
one its `helm_import_repository` fetches.""",
            allow_files = [".tgz"],
        ),
        "include_prefix": attr.string(
            doc = """The directory below a depending kustomization's root at which this kustomization is placed.

A kustomization in another repository can't be reached by a relative
path from the kustomizations that use it, so it declares one: with
`include_prefix = "bases/helloWorld"`, every kustomization listing it
in `deps` finds it at `bases/helloWorld`, its own bases alongside.
Left empty, the kustomization keeps its own location, which is what
bases within the same repository want.""",
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
