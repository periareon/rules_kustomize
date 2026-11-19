"""# Bzlmod extension for kustomize."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load(
    "//kustomize/private:repositories.bzl",
    "kustomize_host_repository",
    "kustomize_toolchains_repository",
)
load(
    "//kustomize/private:versions.bzl",
    "DEFAULT_VERSION",
    "PLATFORMS",
    "VERSIONS",
    "archive_name",
    "archive_urls",
    "checksums_urls",
)

visibility("public")

def _binary_repo_name(version, platform):
    return "kustomize__{}_{}".format(version, platform.replace("-", "_"))

def _binary_label(version, platform):
    return "@{}//:{}".format(
        _binary_repo_name(version, platform),
        "kustomize.exe" if platform.startswith("windows") else "kustomize",
    )

def _find_modules(module_ctx):
    """Locate the root module and the `rules_kustomize` module.

    Outside of a root module (e.g. a `bazel mod` query) the root falls back to
    `rules_kustomize` itself.
    """
    root = None
    rules_module = None
    for mod in module_ctx.modules:
        if mod.is_root:
            root = mod
        if mod.name == "rules_kustomize":
            rules_module = mod
    if rules_module == None:
        fail("Unable to find the rules_kustomize module")
    if root == None:
        root = rules_module
    return root, rules_module

def _fetch_checksums(module_ctx, version):
    """Download and parse the `checksums.txt` file of a kustomize release.

    Args:
        module_ctx (module_ctx): The module extension context.
        version (str): The kustomize version, without a leading `v`.

    Returns:
        dict: A mapping of platform name to hex-encoded sha256 digest.
    """
    urls = checksums_urls(version)
    output = "kustomize-{}-checksums.txt".format(version)
    result = module_ctx.download(
        urls,
        output = output,
        allow_fail = True,
    )
    if not result.success:
        fail((
            "Failed to download the kustomize checksums for version `{}`. " +
            "Is `{}` a published kustomize release? Tried: {}"
        ).format(version, version, ", ".join(urls)))

    # Each line holds a hex digest followed by the archive's file name.
    digests = {}
    for line in module_ctx.read(output).splitlines():
        fields = [f for f in line.replace("\t", " ").split(" ") if f]
        if len(fields) != 2 or len(fields[0]) != 64:
            continue
        digests[fields[1]] = fields[0]

    checksums = {}
    for platform in PLATFORMS:
        digest = digests.get(archive_name(version, platform))
        if digest:
            checksums[platform] = digest
    if not checksums:
        fail("Unexpected content in kustomize checksums file {}".format(urls[0]))

    return checksums

def _root_tags(root_mod, rules_mod, kind):
    """The root module's tags of a kind, falling back to `rules_kustomize`'s own."""
    tags = getattr(root_mod.tags, kind)
    if not tags:
        tags = getattr(rules_mod.tags, kind)
    return tags

def _claim(claimed, name, kind):
    previous = claimed.get(name)
    if previous:
        fail("kustomize.{}(name = \"{}\") clashes with kustomize.{}(name = \"{}\")".format(kind, name, previous, name))
    claimed[name] = kind

def _kustomize_impl(module_ctx):
    root_mod, rules_mod = _find_modules(module_ctx)

    toolchain_tags = _root_tags(root_mod, rules_mod, "toolchain")
    host_tools_tags = _root_tags(root_mod, rules_mod, "host_tools")

    # Checksums persisted in the lockfile by a previous evaluation (Bazel 8.5+).
    facts = getattr(module_ctx, "facts", {})
    used_facts = {}

    versions = {}
    for tag in toolchain_tags:
        versions[tag.version] = None

    checksums_by_version = {}
    for version in versions:
        checksums = VERSIONS.get(version)
        if checksums == None:
            checksums = facts.get(version)
        if checksums == None:
            checksums = _fetch_checksums(module_ctx, version)

        if version not in VERSIONS:
            used_facts[version] = checksums

        checksums_by_version[version] = {
            platform: sha256
            for platform, sha256 in checksums.items()
            if platform in PLATFORMS
        }

        for platform, sha256 in checksums_by_version[version].items():
            # Each archive holds the bare binary at its root.
            http_archive(
                name = _binary_repo_name(version, platform),
                urls = archive_urls(version, platform),
                sha256 = sha256,
                build_file_content = """exports_files(glob(["kustomize*"]))""",
            )

    claimed = {}

    # --- Toolchain hubs: one per `toolchain` tag, covering every platform ---

    hub_platforms = {}
    for tag in toolchain_tags:
        _claim(claimed, tag.name, "toolchain")
        hub_platforms[tag.name] = list(checksums_by_version[tag.version].keys())
        binaries = {}
        exec_compatible_with = {}
        for platform in checksums_by_version[tag.version]:
            name = platform.replace("-", "_")
            binaries[name] = _binary_label(tag.version, platform)
            exec_compatible_with[name] = PLATFORMS[platform].constraints

        kustomize_toolchains_repository(
            name = tag.name,
            binaries = binaries,
            exec_compatible_with = exec_compatible_with,
            version = tag.version,
        )

    # --- Host repositories: one per `host_tools` tag, wrapping a hub ---

    for tag in host_tools_tags:
        _claim(claimed, tag.name, "host_tools")
        if tag.toolchains not in hub_platforms:
            fail("kustomize.host_tools(name = \"{}\") refers to toolchain hub \"{}\", which no kustomize.toolchain() tag declares".format(
                tag.name,
                tag.toolchains,
            ))
        kustomize_host_repository(
            name = tag.name,
            hub = tag.toolchains,
            platforms = hub_platforms[tag.toolchains],
        )

    kwargs = {"reproducible": True}

    # Bazel 8.5+ persists facts in the lockfile so later evaluations (and
    # airgapped builds) never re-download the checksum files.
    if hasattr(module_ctx, "facts"):
        kwargs["facts"] = used_facts

    return module_ctx.extension_metadata(**kwargs)

_toolchain = tag_class(
    doc = """\
Fetch kustomize and create a hub of toolchains for it.

Each tag creates a hub repository (default `@kustomize_toolchains`) holding a \
toolchain for every platform kustomize is released on. Register them all with \
`@{name}//:all`; Bazel picks the one matching the execution platform:

```python
kustomize = use_extension("@rules_kustomize//kustomize:extensions.bzl", "kustomize")
kustomize.toolchain(version = "5.7.1")
use_repo(kustomize, "kustomize_toolchains")

register_toolchains("@kustomize_toolchains//:all")
```

`rules_kustomize` declares and registers a `kustomize_toolchains` hub for the \
default version itself, so a root module without any `toolchain` tag needs \
nothing further. A root module's tags replace that default, so declaring a \
hub with the same name changes the version the registered toolchains serve. \
Hubs with other names are only used once registered.

### Versions

`rules_kustomize` ships checksums for a single default version. Requesting any \
other version makes the extension download that release's `checksums.txt` file \
while it is evaluated. On Bazel 8.5 and newer the digests are then stored as \
facts in `MODULE.bazel.lock`, so the lookup only happens once per version and \
airgapped builds work from the lockfile. Older Bazel versions repeat the lookup \
whenever the extension is re-evaluated.
""",
    attrs = {
        "name": attr.string(
            doc = "The name of the hub repository.",
            default = "kustomize_toolchains",
        ),
        "version": attr.string(
            doc = "The version of kustomize to fetch, without a leading `v`.",
            default = DEFAULT_VERSION,
        ),
    },
)

_host_tools = tag_class(
    doc = """\
Expose the host platform's kustomize from a toolchain hub for `bazel run`.

Each tag creates a repository (default `@kustomize`) whose `//:kustomize` \
target runs the kustomize that the named hub (default `kustomize_toolchains`) \
holds for the host platform. It runs from the directory `bazel run` was \
invoked in, so relative paths such as `build ./overlay` resolve as they would \
for a locally installed kustomize:

```python
kustomize.host_tools()
use_repo(kustomize, "kustomize")
```

```bash
bazel run @kustomize -- build ./deploy/overlays/dev
```

Several versions can live side by side by pairing each hub with a host \
repository of its own:

```python
kustomize.toolchain(name = "kustomize_legacy_toolchains", version = "5.6.0")
kustomize.host_tools(name = "kustomize_legacy", toolchains = "kustomize_legacy_toolchains")
use_repo(kustomize, "kustomize_legacy")
```
""",
    attrs = {
        "name": attr.string(
            doc = "The name of the host repository.",
            default = "kustomize",
        ),
        "toolchains": attr.string(
            doc = "The name of the toolchain hub, declared by a `toolchain` tag, to take the host platform's kustomize from.",
            default = "kustomize_toolchains",
        ),
    },
)

kustomize = module_extension(
    doc = "Module extension for fetching kustomize.",
    implementation = _kustomize_impl,
    tag_classes = {
        "host_tools": _host_tools,
        "toolchain": _toolchain,
    },
)
