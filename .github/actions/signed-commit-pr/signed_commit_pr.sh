#!/bin/bash

# Commits the working tree and opens (or updates) a pull request whose commit is
# signed. Invoked by `.github/actions/signed-commit-pr/action.yml`.
#
# We have no signing key on the runner, but GitHub signs any commit created through
# its own API, which is how `peter-evans/create-pull-request` implements
# `sign-commits: true`. It does so by uploading every changed file as an individual
# blob API call, taking over 10 minutes for the ~640 lockfiles a release touches.
#
# Uploading blobs is only a way to get the tree onto the server, and `git push` does
# that in a single packfile. So: commit and push with plain `git`, then re-create the
# identical tree as a commit through the API so GitHub signs it, and repoint the
# branch at that signed commit. Three API calls instead of one per changed file.
#
# Like `create-pull-request`, the branch ends up with a single commit on top of base
# and is force-pushed, so re-runs update an open PR in place.

set -euo pipefail

: "${GH_TOKEN:?}" "${REPO:?}" "${BRANCH:?}" "${BASE:?}" "${TITLE:?}" "${COMMIT_MESSAGE:?}" "${BODY:?}"

# Splits a comma- or newline-separated input into the `entries` array, trimming
# whitespace and dropping blanks. Entries are never word-split or globbed by the
# shell, so pathspecs such as `tools/*.lock` reach git verbatim.
entries=()
split_list() {
  entries=()
  local item
  while IFS= read -r item; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    if [ -n "$item" ]; then
      entries+=("$item")
    fi
  done < <(printf '%s\n' "$1" | tr ',' '\n')
}

# `${PATHS-.}` rather than `${PATHS:-.}`: an unset value means the whole working tree,
# but a blank one is a caller mistake and must not silently widen to everything.
split_list "${PATHS-.}"
pathspecs=(${entries[@]+"${entries[@]}"})
if [ "${#pathspecs[@]}" -eq 0 ]; then
  echo "::error::The 'paths' input is blank; pass pathspecs to commit, or omit it to commit the whole tree" >&2
  exit 1
fi

split_list "${LABELS:-}"
create_label_args=()
edit_label_args=()
for label in ${entries[@]+"${entries[@]}"}; do
  create_label_args+=(--label "$label")
  edit_label_args+=(--add-label "$label")
done

base_sha=$(git rev-parse HEAD)
git checkout -B "$BRANCH"
git add -A -- "${pathspecs[@]}"

if git diff --cached --quiet; then
  if [ "${FAIL_IF_EMPTY:-false}" = "true" ]; then
    echo "::error::Nothing to commit under ${pathspecs[*]}" >&2
    exit 1
  fi
  echo "Nothing to commit under ${pathspecs[*]}; skipping the pull request"
  exit 0
fi

# This identity is discarded along with the local commit: GitHub attributes the signed
# commit below to the token's own identity, and commits it as `GitHub <noreply@…>`.
git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit --quiet -m "$COMMIT_MESSAGE"

# Pushed first so the blobs and trees exist on GitHub. This commit is unsigned and is
# replaced right below; nothing observes it in the meantime, as no workflow triggers on
# pushes to these branches and the PR head is only read once the PR is opened.
#
# Pushing with our own credential, rather than relying on the checkout having persisted
# one, keeps this working for the callers that use `persist-credentials: false`. The
# helper reads the token from the environment, so it reaches neither argv nor
# .git/config; the leading `credential.helper=` clears any inherited helpers.
git -c credential.helper= \
    -c 'credential.helper=!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$GH_TOKEN"; }; f' \
    push --force "${GITHUB_SERVER_URL:-https://github.com}/${REPO}.git" "HEAD:refs/heads/${BRANCH}"

commit=$(gh api "repos/${REPO}/git/commits" \
  -f "message=${COMMIT_MESSAGE}" \
  -f "tree=$(git rev-parse 'HEAD^{tree}')" \
  -f "parents[]=${base_sha}")

sha=$(printf '%s' "$commit" | jq -r '.sha')
verified=$(printf '%s' "$commit" | jq -r '.verification.verified')
reason=$(printf '%s' "$commit" | jq -r '.verification.reason')

if [ "$verified" != "true" ]; then
  echo "::error::Commit ${sha} is not signed (reason: ${reason}); refusing to open the pull request" >&2
  exit 1
fi

echo "Created signed commit ${sha} (verification: ${reason})"
gh api --silent --method PATCH "repos/${REPO}/git/refs/heads/${BRANCH}" -f "sha=${sha}" -F force=true

# The force-push above already moved an open PR's head, so only the title, body and
# labels need refreshing; `gh pr create` fails outright when one is already open.
url=$(gh pr list --repo "$REPO" --head "$BRANCH" --base "$BASE" --state open --json url --jq '.[0].url // empty')
if [ -n "$url" ]; then
  gh pr edit "$url" --title "$TITLE" --body "$BODY" ${edit_label_args[@]+"${edit_label_args[@]}"}
  echo "Updated pull request ${url}"
else
  url=$(gh pr create --repo "$REPO" --base "$BASE" --head "$BRANCH" \
    --title "$TITLE" --body "$BODY" ${create_label_args[@]+"${create_label_args[@]}"})
  echo "Created pull request ${url}"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "pull-request-url=${url}"; echo "commit-sha=${sha}"; } >> "$GITHUB_OUTPUT"
fi
