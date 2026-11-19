"""Constants for accessing kustomize binaries."""

visibility(["//kustomize/...", "//test/..."])

DEFAULT_VERSION = "5.8.3"

# Format arguments are `{version}` (without a leading `v`), `{os}`,
# `{arch}` and `{ext}`.
URL_TEMPLATES = [
    "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv{version}/kustomize_v{version}_{os}_{arch}.{ext}",
]

# Format argument is `{version}`.
CHECKSUMS_URL_TEMPLATES = [
    "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv{version}/checksums.txt",
]

def _platform(os, arch, constraints):
    return struct(
        os = os,
        arch = arch,
        constraints = constraints,
    )

# Platforms kustomize is released for, keyed by the `{os}-{arch}` name
# used upstream.
PLATFORMS = {
    "darwin-amd64": _platform("darwin", "amd64", ["@platforms//os:macos", "@platforms//cpu:x86_64"]),
    "darwin-arm64": _platform("darwin", "arm64", ["@platforms//os:macos", "@platforms//cpu:aarch64"]),
    "linux-amd64": _platform("linux", "amd64", ["@platforms//os:linux", "@platforms//cpu:x86_64"]),
    "linux-arm64": _platform("linux", "arm64", ["@platforms//os:linux", "@platforms//cpu:aarch64"]),
    "linux-ppc64le": _platform("linux", "ppc64le", ["@platforms//os:linux", "@platforms//cpu:ppc64le"]),
    "linux-s390x": _platform("linux", "s390x", ["@platforms//os:linux", "@platforms//cpu:s390x"]),
    "windows-amd64": _platform("windows", "amd64", ["@platforms//os:windows", "@platforms//cpu:x86_64"]),
    "windows-arm64": _platform("windows", "arm64", ["@platforms//os:windows", "@platforms//cpu:aarch64"]),
}

# Checksums are recorded for a single version. Other versions have
# their checksums looked up from the release's `checksums.txt` file
# and persisted as module extension facts.
VERSIONS = {
    "5.8.3": {
        "darwin-amd64": "d08fb85846c3d977f0e2a66e7ff45f1b5264c294685e5e726e1a8bdfe0da8dee",
        "darwin-arm64": "4cbb08e209d8fff47cd60bfb6407daaf5ee699f9b9295849a1065024fac2d1ef",
        "linux-amd64": "cb9e31198d3f63b44848bd0afc4c8efc56e6cfef9c93a4a39a211940e6decd61",
        "linux-arm64": "9867b76482cfc6d25b546abc1d2b5a32bd137505aba640649b4b378f64f6d68f",
        "linux-ppc64le": "ff2f0b1f90cca3c14aae949d755c4796f4307d7cdb7bc6b7375044caf15814cb",
        "linux-s390x": "b3f3bea8f941cae63d7fcd358dabc886498ba85ed628ff5a3b21da62e52d9db7",
        "windows-amd64": "763c4040ff01435bfce39661072452ebdf1cf2808bb91f5708ab4420834fbd42",
        "windows-arm64": "b86236917e649e2f9531899c519f333e554cd1fc0c87132b86b885bf315735dc",
    },
}

def archive_extension(platform):
    """Return the extension of the release archive for a platform.

    Args:
        platform (str): A key of `PLATFORMS`.

    Returns:
        str: `zip` or `tar.gz`.
    """
    if platform.startswith("windows"):
        return "zip"
    return "tar.gz"

def archive_name(version, platform):
    """Return the file name of a kustomize release archive.

    Args:
        version (str): The kustomize version, without a leading `v`.
        platform (str): A key of `PLATFORMS`.

    Returns:
        str: e.g. `kustomize_v5.8.3_linux_amd64.tar.gz`.
    """
    info = PLATFORMS[platform]
    return "kustomize_v{}_{}_{}.{}".format(version, info.os, info.arch, archive_extension(platform))

def archive_urls(version, platform):
    """Return the download URLs for a kustomize release archive.

    Args:
        version (str): The kustomize version, without a leading `v`.
        platform (str): A key of `PLATFORMS`.

    Returns:
        list: URLs to try in order.
    """
    info = PLATFORMS[platform]
    return [
        template.format(
            version = version,
            os = info.os,
            arch = info.arch,
            ext = archive_extension(platform),
        )
        for template in URL_TEMPLATES
    ]

def checksums_urls(version):
    """Return the download URLs for a kustomize release's checksum file.

    Args:
        version (str): The kustomize version, without a leading `v`.

    Returns:
        list: URLs to try in order.
    """
    return [template.format(version = version) for template in CHECKSUMS_URL_TEMPLATES]
