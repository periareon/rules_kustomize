"""kustomize toolchain rules."""

load(":plugin.bzl", "KustomizePluginInfo", "plugin_entries")

visibility("//kustomize/...")

def _rlocationpath(file, workspace_name):
    """Return the runfiles path of `file`, as `$(rlocationpath)` would."""
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)

def _manifest_entry(entry):
    return [entry.path, entry.file.path]

def _plugin_home(ctx, base):
    """Assemble the toolchain's plugins into a plugin home directory.

    Args:
        ctx: The rule context.
        base: The `ToolchainInfo` of the base toolchain, if any, whose
            plugin home is copied in first.
    """
    entries = []
    for plugin in ctx.attr.plugins:
        entries.extend(plugin_entries(plugin[KustomizePluginInfo]))

    seen = {}
    for entry in entries:
        if entry.path in seen:
            fail("plugins {} and {} both provide {}".format(seen[entry.path], entry.file.short_path, entry.path))
        seen[entry.path] = entry.file.short_path

    home = ctx.actions.declare_directory("{}.plugins".format(ctx.label.name))

    manifest = ctx.actions.args()
    manifest.add_all(entries, map_each = _manifest_entry)
    manifest.set_param_file_format("multiline")
    manifest.use_param_file("--manifest=%s", use_always = True)

    # Directories go through `add_all` without expansion, so that path
    # mapping still sees them as files.
    args = ctx.actions.args()
    args.add_all([home], before_each = "--output", expand_directories = False)
    inputs = [entry.file for entry in entries]
    base_home = getattr(base, "plugin_home", None) if base else None
    if base_home:
        args.add_all([base_home], before_each = "--base", expand_directories = False)
        inputs.append(base_home)

    ctx.actions.run(
        mnemonic = "KustomizePluginHome",
        progress_message = "Assembling kustomize plugins for %{label}",
        executable = ctx.executable._plugin_home,
        arguments = [manifest, args],
        inputs = inputs,
        outputs = [home],
        toolchain = None,
        execution_requirements = {"supports-path-mapping": "1"},
    )
    return home

def _kustomize_toolchain_impl(ctx):
    if bool(ctx.attr.kustomize) == bool(ctx.attr.base):
        fail("exactly one of `kustomize` and `base` must be set for {}".format(ctx.label))

    base = ctx.attr.base[platform_common.ToolchainInfo] if ctx.attr.base else None
    binary = base.kustomize if base else ctx.file.kustomize
    version = ctx.attr.version or (base.version if base else "")
    plugin_home = _plugin_home(ctx, base)

    template_variables = platform_common.TemplateVariableInfo({
        "KUSTOMIZE": binary.path,
        "KUSTOMIZE_PLUGIN_HOME": plugin_home.path,
        "KUSTOMIZE_PLUGIN_HOME_RLOCATIONPATH": _rlocationpath(plugin_home, ctx.workspace_name),
        "KUSTOMIZE_RLOCATIONPATH": _rlocationpath(binary, ctx.workspace_name),
    })

    default_info = DefaultInfo(
        files = depset([binary, plugin_home]),
        runfiles = ctx.runfiles(files = [binary, plugin_home]),
    )

    toolchain_info = platform_common.ToolchainInfo(
        default_info = default_info,
        kustomize = binary,
        plugin_home = plugin_home,
        template_variables = template_variables,
        version = version,
    )

    return [default_info, toolchain_info, template_variables]

kustomize_toolchain = rule(
    implementation = _kustomize_toolchain_impl,
    doc = """\
A kustomize toolchain.

A toolchain is defined either from a kustomize binary (`kustomize`) or
on top of another toolchain (`base`), adding plugins and arguments to
it. The latter is how a workspace registers a toolchain of its own with
plugins while leaving the download of kustomize to the module extension:

```python
kustomize_toolchain(
    name = "with_plugins_impl",
    base = "@kustomize//:toolchain",
    plugins = [":my_plugin"],
)

toolchain(
    name = "with_plugins",
    toolchain = ":with_plugins_impl",
    toolchain_type = "@rules_kustomize//kustomize:toolchain_type",
)
```

Rules consume it through `@rules_kustomize//kustomize:toolchain_type`. The
`ToolchainInfo` carries `kustomize` (the binary `File`), `plugin_home` (a
directory laid out for `KUSTOMIZE_PLUGIN_HOME`, holding the toolchain's
`plugins`) and `version` (a string, possibly empty).

`@rules_kustomize//kustomize:current_toolchain` exposes those through make
variables: `KUSTOMIZE` and `KUSTOMIZE_PLUGIN_HOME` are execpaths, for use in
actions, and `KUSTOMIZE_RLOCATIONPATH` and
`KUSTOMIZE_PLUGIN_HOME_RLOCATIONPATH` are rlocationpaths, for looking them up
in runfiles.
""",
    attrs = {
        "base": attr.label(
            doc = "A kustomize toolchain to build on, supplying the binary, version, plugins and extra arguments this one adds to. Exactly one of `kustomize` and `base` must be set.",
            providers = [platform_common.ToolchainInfo],
            cfg = "exec",
        ),
        "kustomize": attr.label(
            doc = "A kustomize binary. Exactly one of `kustomize` and `base` must be set.",
            allow_single_file = True,
            cfg = "exec",
        ),
        "plugins": attr.label_list(
            doc = "Plugins available to every build using this toolchain, and to `bazel run` through a host repository.",
            cfg = "exec",
            providers = [KustomizePluginInfo],
        ),
        "version": attr.string(
            doc = "The version of kustomize, without a leading `v`. Informational; defaults to the base toolchain's.",
        ),
        "_plugin_home": attr.label(
            default = Label("//kustomize/private/plugin_home"),
            executable = True,
            cfg = "exec",
        ),
    },
)

def _kustomize_toolchain_alias_impl(ctx):
    toolchain_info = ctx.toolchains[Label("//kustomize:toolchain_type")]
    return [
        toolchain_info,
        toolchain_info.default_info,
        toolchain_info.template_variables,
    ]

kustomize_toolchain_alias = rule(
    implementation = _kustomize_toolchain_alias_impl,
    doc = """\
Exposes the kustomize toolchain Bazel resolved for the current platform.
Workaround for https://github.com/bazelbuild/bazel/issues/14009
""",
    toolchains = [str(Label("//kustomize:toolchain_type"))],
)
