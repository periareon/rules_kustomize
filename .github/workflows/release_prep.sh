#!/usr/bin/env bash

# This program is adapted from "release_prep.sh" in rules_template:
# https://github.com/bazel-contrib/rules-template/blob/main/.github/workflows/release_prep.sh
#
# The reusable "release_ruleset" workflow from "bazel-contrib/.github"
# insists on this path. It expects the release archive in the working
# directory and the release notes on standard output.

set -e -u -o pipefail

# The reusable "release_ruleset" workflow runs this program with only
# the Git tag as its argument; the ruleset name then comes from the
# repository's name.
if (($# >= 2)); then
  ruleset_name="$1"
  shift
else
  ruleset_name="${GITHUB_REPOSITORY##*/}"
fi
if [ -z "${ruleset_name}" ]; then
  echo >&2 'Bazel ruleset name must not be empty.'
  exit 1
fi

if (($# < 1)); then
  git_tag="${GITHUB_REF_NAME:-}"
else
  git_tag="$1"
  shift
fi
if [ -z "${git_tag}" ]; then
  echo >&2 'Git tag to use for release must not be empty.'
  exit 1
fi

# Work around lack of the annotated tag for the motivating tag
# being present unless we fetch at depth zero (meaning fetch all
# history, with no depth restriction).
#
# Pertinent issues and PRs:
#   https://github.com/actions/checkout/issues/338
#   https://github.com/actions/checkout/issues/448
#   https://github.com/actions/checkout/issues/701
#   https://github.com/actions/checkout/pull/579
#
# Basis of inspiration:
#   https://github.com/actions/checkout/issues/701#issuecomment-1139627817
#   https://stackoverflow.com/a/54635270
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  git fetch origin \
    --no-tags \
    "+refs/tags/${git_tag}:refs/tags/${git_tag}"
fi

# The prefix is chosen to match what GitHub generates for its own
# source archives.
git archive \
  --format=tar \
  --prefix="${ruleset_name}-${git_tag:1}/" \
  "${git_tag}" |
  gzip >"vcs-archive-${git_tag}.tar.gz"

tag_annotation_subject=$(git tag --list --format='%(contents:subject)' "${git_tag}")
if [ -n "${tag_annotation_subject}" ]; then
  echo "# ${tag_annotation_subject}"
  tag_annotation_body=$(git tag --list --format='%(contents:body)' "${git_tag}")
  if [ -n "${tag_annotation_body}" ]; then
    echo "
${tag_annotation_body}
"
  fi
  echo "# Details"
fi

cat <<EOF
## Using this ruleset in a Bazel module

Add the following directive to your _MODULE.bazel_ file:
\`\`\`starlark
bazel_dep(name = "${ruleset_name}", version = "${git_tag:1}")
\`\`\`

## Verifying the release archive

The archive comes with a SLSA build provenance attestation, which the GitHub CLI can check:
\`\`\`shell
gh attestation verify vcs-archive-${git_tag}.tar.gz --repo ${GITHUB_REPOSITORY:-seh/rules_kustomize}
\`\`\`
EOF
