"""Helpers describing where a kustomization's files sit in the staging tree."""

load("@bazel_skylib//lib:paths.bzl", "paths")

visibility("//kustomize/...")

def staged_path(file, workspace_name):
    """Return where a file is staged, mirroring Bazel's runfiles layout.

    Files in the main repository sit below the workspace name, and files
    in other repositories below their repository's canonical name.

    Args:
        file (File): The file to stage.
        workspace_name (str): `ctx.workspace_name`.

    Returns:
        str: A slash separated path relative to the staging root.
    """
    short_path = file.short_path
    if short_path.startswith("../"):
        return short_path[len("../"):]
    return paths.join(workspace_name, short_path)

def relative_path(path, base):
    """Return `path` relative to the directory `base`.

    Both must be normalized, slash separated, relative paths.

    Args:
        path (str): The path to express relative to `base`.
        base (str): The directory to express `path` relative to.

    Returns:
        str: A relative path, using `..` segments where `path` leaves `base`.
    """
    path_parts = [p for p in path.split("/") if p]
    base_parts = [p for p in base.split("/") if p]
    common = 0
    for i in range(min(len(path_parts), len(base_parts))):
        if path_parts[i] != base_parts[i]:
            break
        common = i + 1
    return "/".join([".."] * (len(base_parts) - common) + path_parts[common:])
