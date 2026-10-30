# Contributor CI

Approving a fork's workflow run permits its code to execute on the configured
runners. GitHub still withholds repository secrets, write access, and OIDC
credentials. Tests must work within that boundary.

## Validation and reporting

`pull_request` workflows build and test the proposed code with public
dependencies and local test services. Zizmor uses the read-only GitHub token on
PRs; trusted master pushes retain the read-only STS policy.

JUnit and coverage artefacts remain available on fork runs. Datadog exports and
pipeline tagging are optional and excluded from fork execution. Typing statistics
are computed without write credentials and published as a run summary and an
artefact.

Each validation workflow has a completion job that checks its dependencies even
when they fail or are skipped. Path-filtered workflows explicitly accept a skip
only when their change detector succeeded and found no relevant changes.

`all-green.yml` rejects failing checks except the named optional reporting and
metadata jobs. It then checks that every expected completion check actually ran
and succeeded. When adding a validation workflow, update
`scripts/ci/required_checks.rb`. A missing or skipped required check is not a pass.

## Trusted metadata workflows

Labelling, cache cleanup, and milestone assignment use `pull_request_target`.
They execute trusted default-branch code, never the PR checkout. Milestone
assignment reads the merged version file as data instead of evaluating its
gemspec or Ruby source.

`typing-stats-comment.yml` uses `workflow_run` and verifies the producing
workflow, run attempt, source repository, current PR head, and report identity.
It publishes a link to the run summary, without downloading report contents.
Only an existing comment from the STS app can be updated. An ambiguous or stale
PR association produces no comment.

Publishing failures produce warnings. The `workflow_run` check attaches to the
default branch, so it must not turn a reporting outage into a validation failure.

Write-token policies in `chainguard/` are bound to these trusted workflow refs
and events. A workflow condition alone does not restrict what an STS token can
authorise.

## Release and cache provenance

Release/changelog branch-name exceptions apply only to upstream branches.
Contributors cannot gain an exception by choosing the same name in their fork.

The timing collector accepts successful upstream `push` runs only. A fork branch
named `master` must not seed the default-branch timing cache.

## Local verification

```sh
nix develop --command bundle exec rake test:github
nix run nixpkgs#actionlint -- .github/workflows/*.yml .github/workflows/*.yaml
nix run nixpkgs#yamllint -- --strict .github
nix run nixpkgs#shellcheck -- .github/scripts/check_changelog_release_only.sh .github/scripts/download_timing_artifacts.sh
```

These checks do not require approving or triggering a hosted workflow.
