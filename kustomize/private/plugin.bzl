"""The `kustomize_plugin` rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")

visibility("//kustomize/...")

KustomizePluginInfo = provider(
    doc = "A kustomize plugin, placed below a plugin home for kustomize to find.",
    fields = {
        "api_version": "str: The `apiVersion` of the plugin's configuration objects, such as `example.com/v1`.",
        "binary": "File: The plugin's executable (or Go plugin `.so` file).",
        "data": "Depset[File]: Additional files placed next to the plugin.",
        "kind": "str: The `kind` of the plugin's configuration objects, such as `Greeter`.",
    },
)

def plugin_entries(info):
    """Lay a plugin out the way kustomize looks it up.

    kustomize finds a legacy plugin below the plugin home at
    `<apiVersion>/<lowercased kind>/<Kind>`, with the file named exactly
    after the kind (plus `.so` for Go plugins).

    Args:
        info (KustomizePluginInfo): The plugin.

    Returns:
        list: `struct(path, file)` pairs, with `path` relative to the plugin home.
    """
    directory = paths.join(info.api_version, info.kind.lower())
    binary_name = info.kind + ".so" if info.binary.basename.endswith(".so") else info.kind
    entries = [struct(path = paths.join(directory, binary_name), file = info.binary)]
    for data in info.data.to_list():
        entries.append(struct(path = paths.join(directory, data.basename), file = data))
    return entries

def _kustomize_plugin_impl(ctx):
    if bool(ctx.attr.binary) == bool(ctx.attr.library):
        fail("exactly one of `binary` and `library` must be set for {}".format(ctx.label))
    return [
        KustomizePluginInfo(
            api_version = ctx.attr.api_version,
            binary = ctx.executable.binary if ctx.attr.binary else ctx.file.library,
            data = depset(ctx.files.data),
            kind = ctx.attr.kind,
        ),
    ]

kustomize_plugin = rule(
    doc = """Defines a legacy kustomize plugin.

The plugin is placed below a plugin home at `<api_version>/<kind>/<Kind>`,
where kustomize looks for the plugin backing configuration objects of that
`apiVersion` and `kind`, when listed in a `kustomize_toolchain`'s or a
`kustomized_resources` target's `plugins`.

An exec plugin receives the path of its configuration object as its only
argument and the resources to transform on standard input, and writes
resources to standard output. It runs from the kustomization root, with
no runfiles of its own, so it must be self contained apart from `data`.""",
    implementation = _kustomize_plugin_impl,
    attrs = {
        "api_version": attr.string(
            doc = "The `apiVersion` of the plugin's configuration objects, such as `example.com/v1`.",
            mandatory = True,
        ),
        "binary": attr.label(
            doc = "The executable implementing an exec plugin. Exactly one of `binary` and `library` must be set.",
            executable = True,
            cfg = "exec",
        ),
        "data": attr.label_list(
            doc = "Additional files placed next to the plugin.",
            allow_files = True,
        ),
        "kind": attr.string(
            doc = "The `kind` of the plugin's configuration objects, such as `Greeter`. The plugin file is named after it.",
            mandatory = True,
        ),
        "library": attr.label(
            doc = "The shared object implementing a Go plugin. Exactly one of `binary` and `library` must be set.",
            allow_single_file = [".so"],
            cfg = "exec",
        ),
    },
    provides = [KustomizePluginInfo],
)
