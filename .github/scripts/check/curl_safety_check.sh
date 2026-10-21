#!/bin/bash
set -euo pipefail

# Flags newly added/modified curl invocations in CI scripts, GitHub Actions
# workflows, and Dockerfiles that are missing fail-on-HTTP-error (-f/--fail)
# and/or retry (--retry) flags, per AGENTS.md's "Shell scripts" guidance:
# curl must fail on HTTP errors and retry. Without -f, a 4xx/5xx response
# exits 0 and an error page is silently used as the real download; without
# --retry, a transient network blip fails the whole job. Scoped to the diff
# (not the whole repo) so pre-existing calls are never retroactively
# flagged. Intentional exceptions (for example, a call that polls its own
# exit status in a loop) can opt out with a trailing comment containing the
# text "curl safety ok" plus a reason.
#
# Only meaningful for pull_request events, where GitHub populates
# GITHUB_BASE_REF automatically; silently no-ops otherwise (for example, on
# a push to master) since there is no PR diff to scope the check to.

if [[ -z "${GITHUB_BASE_REF:-}" ]]; then
  echo "Skipping curl safety check: not a pull_request event (GITHUB_BASE_REF unset)"
  exit 0
fi

# The checkout step for this job uses the default shallow, single-branch
# fetch, so the base branch's history isn't locally available yet. Fetch it
# (unshallowing if necessary) so a merge-base diff against it is possible.
git fetch --quiet origin "${GITHUB_BASE_REF}" || true
if ! git merge-base HEAD "origin/${GITHUB_BASE_REF}" >/dev/null 2>&1; then
  git fetch --quiet --unshallow origin "${GITHUB_BASE_REF}" 2>/dev/null \
    || git fetch --quiet --depth=1000 origin "${GITHUB_BASE_REF}"
fi

violations=""

while IFS= read -r line; do
  case "$line" in
    "+++ "*)
      file="${line#+++ }"
      file="${file#b/}"
      continue
      ;;
    "+"*)
      ;;
    *)
      continue
      ;;
  esac

  content="${line#+}"

  # Only consider shell scripts, GitHub Actions workflows, and Dockerfiles.
  case "${file:-}" in
    *.sh | *.yml | *.yaml | *Dockerfile*) ;;
    *) continue ;;
  esac

  # Skip comment lines so prose that merely mentions "curl" (docs, code
  # comments explaining this very check) is never flagged.
  if [[ "$content" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  # Only treat this as a real curl invocation if "curl" is immediately
  # followed by whitespace and then a flag, a shell variable, or a URL.
  # This avoids matching job/step names like "curl-safety" or filenames
  # like "curl_safety_check.sh".
  if ! grep -qP '(?<![\w.-])curl\s+['"'"'"]?(-|\$|https?://)' <<<"$content"; then
    continue
  fi

  # Explicit opt-out for calls that verify success another way (for
  # example, a status-polling loop that checks the response body/code
  # itself).
  if grep -qi 'curl safety ok' <<<"$content"; then
    continue
  fi

  has_fail=false
  if grep -qP '(^|\s)(-\w*f\w*|--fail)(\s|$)' <<<"$content"; then
    has_fail=true
  fi

  has_retry=false
  if grep -qP '(^|\s)--retry\b' <<<"$content"; then
    has_retry=true
  fi

  if [[ "$has_fail" != true || "$has_retry" != true ]]; then
    violations="${violations}${file}: ${content}"$'\n'
  fi
done < <(git diff --no-color -U0 "origin/${GITHUB_BASE_REF}...HEAD")

if [[ -n "$violations" ]]; then
  echo "::error::New curl calls in CI scripts, workflows, or Dockerfiles must fail on HTTP errors and retry (both -f/--fail and --retry; see AGENTS.md's Shell scripts section). Add the missing flag(s), or mark an intentional exception with a trailing comment containing 'curl safety ok' plus a reason."
  echo "$violations"
  exit 1
fi

echo "OK: no unsafe new curl calls found in the diff"
