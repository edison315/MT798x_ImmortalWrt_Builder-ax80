#!/usr/bin/env bash
# Resolve the upstream commit, decide whether a rebuild is needed, and emit
# the result for the `build` job.
#
# A build is needed when:
#   - the event is anything other than `schedule` — a push means the builder
#     config changed and workflow_dispatch is an explicit request, so both
#     always rebuild; OR
#   - on a scheduled tick, the latest release for RELEASE_PREFIX does not
#     already record the current upstream SHA.
#
# Required tools: git, gh.
#
# Input env:
#   UPSTREAM_REPO   source repo (owner/name)
#   UPSTREAM_REF    branch, tag, or SHA to build
#   RELEASE_PREFIX  release tag prefix (tags are <prefix>-<ts>-<run id>)
#   EVENT_NAME      github.event_name
#   REPO            this builder repo (owner/name); defaults to $GITHUB_REPOSITORY
#   GH_TOKEN        forwarded to gh
#   GITHUB_OUTPUT   Actions outputs file (when in CI)
#
# Outputs:
#   upstream_sha  resolved upstream commit
#   need          "true" if a build is needed, else "false"

set -euo pipefail

# shellcheck source=scripts/lib/log.sh
source "$(dirname -- "$0")/lib/log.sh"

: "${UPSTREAM_REPO:?UPSTREAM_REPO required}"
: "${UPSTREAM_REF:?UPSTREAM_REF required}"
: "${RELEASE_PREFIX:?RELEASE_PREFIX required}"
EVENT_NAME="${EVENT_NAME:-}"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
command -v git >/dev/null || log::die "git is required"

# Resolve a ref to a commit SHA via the remote.
resolve_sha() {
  local repo="$1" ref="$2" sha
  sha="$(git ls-remote "https://github.com/$repo" "$ref" | awk 'NR==1{print $1}')"
  [[ -n "$sha" ]] || log::die "could not resolve $repo@$ref"
  printf '%s\n' "$sha"
}

up_sha="$(resolve_sha "$UPSTREAM_REPO" "$UPSTREAM_REF")"

# Latest published release body for a prefix; empty when there is none.
latest_body() {
  local prefix="$1"
  [[ -n "$REPO" ]] || return 0
  # Anchored on the tag's timestamp field, so the prefix of one series does
  # not also match another's.
  gh api "repos/$REPO/releases" --jq \
    "[.[] | select(.draft|not) | select(.tag_name | test(\"^${prefix}-[0-9]{8}T[0-9]{6}Z-\"))] | sort_by(.created_at) | reverse | .[0].body // \"\"" \
    2>/dev/null || printf '%s' ""
}

if [[ "$EVENT_NAME" != "schedule" ]]; then
  # push (builder config changed) or manual dispatch (explicit) -> always rebuild.
  need=true
else
  # scheduled tick -> only rebuild when the source moved since the last release.
  body="$(latest_body "$RELEASE_PREFIX")"
  if [[ "$body" == *"$up_sha"* ]]; then
    need=false
  else
    need=true
  fi
fi

log::info "$UPSTREAM_REPO@$UPSTREAM_REF -> ${up_sha:0:12}  build=$need"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Upstream check"
    echo "- \`$UPSTREAM_REPO@$UPSTREAM_REF\` -> \`${up_sha:0:12}\`"
    echo "- need: **$need**"
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "upstream_sha=$up_sha"
    echo "need=$need"
  } >>"$GITHUB_OUTPUT"
fi
