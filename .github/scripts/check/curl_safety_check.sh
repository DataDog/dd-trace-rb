#!/bin/bash
set -euo pipefail

# Flags newly added/modified `curl` invocations in CI scripts, GitHub
# Actions workflows, and Dockerfiles that are missing fail-on-HTTP-error
# (-f/--fail) and/or retry (--retry) flags, per AGENTS.md's "Shell scripts"
# guidance: `curl` must fail on HTTP errors and retry. Without -f, a 4xx/5xx
# response exits 0 and an error page is silently used as the real download;
# without --retry, a transient network blip fails the whole job. Scoped to
# the diff (not the whole repo) so pre-existing calls are never retroactively
# flagged. Intentional exceptions (for example, a call that polls its own
# exit status in a loop) can opt out with a `# curl-safety-ok: <reason>`
# comment on the same line.

if [[ -z "${BASE_REF:-}" ]]; then
  echo "Error: BASE_REF environment variable is not set"
  exit 1
fi

if [[ -z "${PR_HEAD_SHA:-}" ]]; then
  echo "Error: PR_HEAD_SHA environment variable is not set"
  exit 1
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

  # Must contain a `curl` invocation as a standalone word.
  if ! grep -qP '(?<![\w.-])curl\b' <<<"$content"; then
    continue
  fi

  # Explicit opt-out for calls that verify success another way (for example,
  # a status-polling loop that checks the response body/code itself).
  if grep -q 'curl-safety-ok' <<<"$content"; then
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
done < <(git diff --no-color -U0 "origin/${BASE_REF}...${PR_HEAD_SHA}")

if [[ -n "$violations" ]]; then
  echo "::error::New curl calls in CI scripts, workflows, or Dockerfiles must fail on HTTP errors and retry (both -f/--fail and --retry; see AGENTS.md#shell-scripts). Add the missing flag(s), or mark an intentional exception with a trailing '# curl-safety-ok: <reason>' comment."
  echo "$violations"
  exit 1
fi

echo "OK: no unsafe new curl calls found in the diff"
