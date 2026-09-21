// Verify that all GitHub Actions check runs for a commit are passing.
//
// Runs inside `actions/github-script` in the publish workflow. Lists every check suite
// for the commit SHA from a specific GitHub App (APP_ID), then inspects individual check
// runs inside any suite that isn't success/neutral/skipped. Fails the workflow if any
// non-excluded check run has a failing conclusion.
//
// Self-exclusion (CURRENT_RUN_ID):
//
//   When a publish attempt fails, its check suite stays attached to the commit as a
//   permanent failure. A subsequent publish dispatch on the same SHA creates a *new*
//   workflow run (and check suite) — it does not reuse the old one. Without exclusion,
//   the new run's verification step sees the old run's failed check suite and fails
//   itself, creating a cascade where a single publish failure blocks all retries.
//
//   To break this cycle, the script accepts CURRENT_RUN_ID (the current workflow run ID).
//   It looks up which workflow the run belongs to, finds all runs of that workflow on
//   this SHA, and excludes their check runs from the failure list. This means publish
//   runs only evaluate CI check runs — not other publish runs.
//
//   The lookup is deferred: workflow run API calls only happen when there are actual
//   failures to investigate. On the happy path (all suites green), no extra calls are made.
//
// Limitation — aggregate status endpoint:
//
//   The publish workflow has a separate "Verify deferred commit data" step that hits
//   GitHub's internal aggregate status endpoint (commit/<sha>/deferred_commit_data).
//   This is the same data that drives the green checkmark / red X in the GitHub UI.
//   That aggregate includes ALL check suites for the SHA with no way to filter individual
//   runs. If old failed publish check suites exist, the aggregate stays red even though
//   this script correctly passes. The `force: true` input bypasses that step.
//
//   "Re-run all jobs" on the *same* workflow run reuses its check suite and can turn it
//   green. A *new* workflow dispatch cannot — the old failure remains.
//
// Environment variables:
//   APP_ID          - GitHub App ID to filter check suites (e.g. 15368 for GitHub Actions)
//   CURRENT_RUN_ID  - (optional) current workflow run ID; enables self-exclusion
//
// API:
// - https://docs.github.com/en/rest/checks/suites#list-check-suites-for-a-git-reference
// - https://docs.github.com/en/rest/checks/runs#list-check-runs-in-a-check-suite
// - https://docs.github.com/en/rest/actions/workflow-runs#get-a-workflow-run
// - https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow
module.exports = async ({github, context, core}) => {
  const checkSuites = await github.paginate(github.rest.checks.listSuitesForRef, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    ref: context.sha,
    app_id: parseInt(process.env.APP_ID),
    per_page: 100
  });

  console.log(`Found ${checkSuites.length} check suites`);

  const failedSuites = checkSuites.filter(suite =>
    suite.status === 'completed' &&
    suite.conclusion !== 'success' &&
    suite.conclusion !== 'neutral' &&
    suite.conclusion !== 'skipped'
  );

  if (failedSuites.length > 0) {
    console.log(`Found ${failedSuites.length} failed check suites`);

    const failedChecksPromises = failedSuites.map(async suite => {
      const checkRuns = await github.paginate(github.rest.checks.listForSuite, {
        owner: context.repo.owner,
        repo: context.repo.repo,
        check_suite_id: suite.id,
        per_page: 100
      });

      return checkRuns.filter(check =>
        check.status === 'completed' &&
        check.conclusion !== 'success' &&
        check.conclusion !== 'neutral' &&
        check.conclusion !== 'skipped'
      );
    });

    const failedChecksArrays = await Promise.all(failedChecksPromises);
    let failedChecks = failedChecksArrays.flat();

    // Exclude check runs from the current workflow to prevent self-referential cascades.
    // Only load workflow runs when there are actual failures to avoid unnecessary API calls.
    const currentWorkflowRunId = parseInt(process.env.CURRENT_RUN_ID);
    let excludedRunIds = new Set();

    if (currentWorkflowRunId) {
      // Get the workflow ID for the current run
      const { data: currentRun } = await github.rest.actions.getWorkflowRun({
        owner: context.repo.owner,
        repo: context.repo.repo,
        run_id: currentWorkflowRunId,
      });
      const workflowId = currentRun.workflow_id;

      // List all runs of this workflow to find their check suite IDs
      const { data: workflowRuns } = await github.rest.actions.listWorkflowRuns({
        owner: context.repo.owner,
        repo: context.repo.repo,
        workflow_id: workflowId,
        head_sha: context.sha,
        per_page: 100,
      });

      excludedRunIds = new Set(workflowRuns.workflow_runs.map(r => r.id));
      console.log(`Found ${excludedRunIds.size} runs of current workflow (ID: ${workflowId})`);
    }

    // html_url format: https://github.com/OWNER/REPO/actions/runs/RUN_ID/job/JOB_ID
    if (excludedRunIds.size > 0) {
      const before = failedChecks.length;
      failedChecks = failedChecks.filter(check => {
        const match = (check.html_url || '').match(/\/actions\/runs\/(\d+)\//);
        if (match) {
          return !excludedRunIds.has(parseInt(match[1]));
        }
        return true;
      });
      const excluded = before - failedChecks.length;
      if (excluded > 0) {
        console.log(`Excluded ${excluded} check runs from current workflow`);
      }
    }

    console.log(`Found a total of ${failedChecks.length} failed check runs (after exclusions)`);

    if (failedChecks.length > 0) {
      failedChecks.forEach(failedCheck => {
        const { name, conclusion, html_url } = failedCheck;
        const message = JSON.stringify({ name, conclusion, url: html_url }, null, 2);

        core.error(message);
      });

      core.setFailed(`Found ${failedChecks.length} failed check runs`);
    }
  }
}
