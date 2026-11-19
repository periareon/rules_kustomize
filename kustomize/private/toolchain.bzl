"""kustomize toolchain rules."""

visibility("//kustomize/...")

def _rlocationpath(file, workspace_name):
    """Return the runfiles path of `file`, as `$(rlocationpath)` would."""
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)

def _kustomize_toolchain_impl(ctx):
    binary = ctx.file.kustomize

    template_variables = platform_common.TemplateVariableInfo({
        "KUSTOMIZE": binary.path,
        "KUSTOMIZE_RLOCATIONPATH": _rlocationpath(binary, ctx.workspace_name),
    })

    default_info = DefaultInfo(
        files = depset([binary]),
        runfiles = ctx.runfiles(files = [binary]),
    )

    toolchain_info = platform_common.ToolchainInfo(
        default_info = default_info,
        kustomize = binary,
        template_variables = template_variables,
        version = ctx.attr.version,
    )

    return [default_info, toolchain_info, template_variables]

kustomize_toolchain = rule(
    implementation = _kustomize_toolchain_impl,
    doc = """\
A kustomize toolchain.

Rules consume it through `@rules_kustomize//kustomize:toolchain_type`. The
`ToolchainInfo` carries `kustomize` (the binary `File`) and `version` (a
string, possibly empty).

`@rules_kustomize//kustomize:current_toolchain` exposes the binary through
two make variables: `KUSTOMIZE` is its execpath, for use in actions, and
`KUSTOMIZE_RLOCATIONPATH` is its rlocationpath, for looking it up in
runfiles.
""",
    attrs = {
        "kustomize": attr.label(
            doc = "A kustomize binary.",
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
        ),
        "version": attr.string(
            doc = "The version of kustomize, without a leading `v`. Informational.",
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
