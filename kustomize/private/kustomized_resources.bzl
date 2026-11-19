"""The `kustomized_resources` rule."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load(":layout.bzl", "staged_path")
load(":plugin.bzl", "KustomizePluginInfo", "plugin_entries")
load(":providers.bzl", "KustomizationInfo")

visibility("//kustomize/...")

_KUSTOMIZE_TOOLCHAIN_TYPE = Label("//kustomize:toolchain_type")
_HELM_TOOLCHAIN_TYPE = Label("@rules_helm//helm:toolchain_type")

# Both tools must resolve for the same execution platform, as kustomize
# invokes helm as a subprocess.
_EXEC_GROUP = "kustomize"

def _manifest_entry(entry):
    # How to stage the file, where to stage it, then where to read it
    # from. Staging puts files from the source tree and from the output
    # tree side by side, as kustomize expects to find them.
    return ["extract" if entry.extract else "copy", entry.path, entry.file.path]

def _plugin_arg(entry):
    return "{}={}".format(entry.path, entry.file.path)

def _kustomized_resources_impl(ctx):
    info = ctx.attr.kustomization[KustomizationInfo]
    toolchains = ctx.exec_groups[_EXEC_GROUP].toolchains
    kustomize_toolchain = toolchains[_KUSTOMIZE_TOOLCHAIN_TYPE]
    kustomize = kustomize_toolchain.kustomize
    result = ctx.outputs.result or ctx.actions.declare_file(ctx.label.name + ".yaml")
    tools = [kustomize]

    # The list of files to stage goes in a params file of its own, so
    # that it never runs into command line length limits.
    manifest = ctx.actions.args()
    manifest.add_all(info.transitive_layout, map_each = _manifest_entry)
    manifest.set_param_file_format("multiline")
    manifest.use_param_file("--manifest=%s", use_always = True)

    args = ctx.actions.args()
    args.add("--kustomize", kustomize)
    args.add("--root", paths.dirname(staged_path(info.target_file, ctx.workspace_name)))
    args.add("--output", result)

    # Whether the kustomization inflates Helm charts is only known once
    # its files can be read, so the builder gets helm whenever a
    # toolchain is available and decides for itself.
    helm_toolchain = toolchains[_HELM_TOOLCHAIN_TYPE]
    if helm_toolchain:
        tools.append(helm_toolchain.helm)
        args.add("--helm", helm_toolchain.helm)

    # Plugins: the toolchain's plugin home, with this target's own laid
    # over it.
    plugin_home = getattr(kustomize_toolchain, "plugin_home", None)
    if plugin_home:
        tools.append(plugin_home)
        args.add_all([plugin_home], before_each = "--plugin_home", expand_directories = False)
    plugin_layout = []
    for plugin in ctx.attr.plugins:
        plugin_layout.extend(plugin_entries(plugin[KustomizePluginInfo]))
    tools.extend([entry.file for entry in plugin_layout])
    args.add_all(plugin_layout, before_each = "--plugin", map_each = _plugin_arg)

    # Everything after this point is passed through to `kustomize build`,
    # the toolchain's extra arguments first so that a build's own, which
    # come last, can override them.
    args.add("--")
    args.add_all(getattr(kustomize_toolchain, "extra_args", []))

    args.add_all(ctx.attr.args)

    ctx.actions.run(
        mnemonic = "KustomizeBuild",
        progress_message = "Building kustomization %{label}",
        executable = ctx.executable._builder,
        arguments = [manifest, args],
        inputs = info.transitive_resources,
        tools = tools,
        outputs = [result],
        # kustomize starts exec functions and plugins with its own
        # environment, so setting the action's is enough: Bazel's action
        # environment (`--action_env`) with the target's `env` on top.
        env = dicts.add(ctx.configuration.default_shell_env, ctx.attr.env),
        exec_group = _EXEC_GROUP,
        # Every path reaches the builder through `Args`, so the action
        # is indifferent to the configuration segment of output paths.
        execution_requirements = {"supports-path-mapping": "1"},
    )

    return [DefaultInfo(files = depset([result]))]

kustomized_resources = rule(
    doc = """Builds a kustomization with `kustomize build`.

The kustomization's files are staged into a private directory tree
before building, so that files from the source tree and generated files
sit together as kustomize expects. The builder reads the staged
kustomization files and enables the Helm chart inflator when one uses
`helmCharts` or `helmGlobals`, and plugins (including exec functions)
when one uses `generators`, `transformers` or `validators`.""",
    implementation = _kustomized_resources_impl,
    attrs = {
        "args": attr.string_list(
            doc = "Additional arguments for this `kustomize build`, placed after every other argument.",
        ),
        "env": attr.string_dict(
            doc = """Environment variables for the build, on top of Bazel's action environment.

kustomize passes its environment on to the exec functions and plugins
it runs, so this is how they are configured.""",
        ),
        "kustomization": attr.label(
            doc = "kustomization to build.",
            providers = [KustomizationInfo],
            mandatory = True,
        ),
        "plugins": attr.label_list(
            doc = "Plugins available to this build, in addition to the toolchain's.",
            cfg = config.exec(_EXEC_GROUP),
            providers = [KustomizePluginInfo],
        ),
        "result": attr.output(
            doc = "The built result, as a YAML stream of KRM resources in separate documents. Defaults to `<name>.yaml`.",
        ),
        "_builder": attr.label(
            default = Label("//kustomize/private/builder"),
            executable = True,
            cfg = config.exec(_EXEC_GROUP),
        ),
    },
    exec_groups = {
        _EXEC_GROUP: exec_group(
            toolchains = [
                _KUSTOMIZE_TOOLCHAIN_TYPE,
                config_common.toolchain_type(
                    _HELM_TOOLCHAIN_TYPE,
                    mandatory = False,
                ),
            ],
        ),
    },
)
