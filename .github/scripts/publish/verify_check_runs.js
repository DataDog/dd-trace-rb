// This script runs in the context of `actions/github-script` from GitHub Action workflow.
// It checks the conclusion for check suites of a commit (SHA) from a specifc Github App.
// It fails the workflow if any of the check suites are not 'success', 'neutral' or 'skipped'.
//
// Check suites belonging to the current workflow are excluded to prevent a cascade where
// a failed publish run blocks all subsequent publish attempts.

// API:
// - https://docs.github.com/en/rest/checks/suites?apiVersion=2022-11-28#list-check-suites-for-a-git-reference
// - https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#list-check-runs-in-a-check-suite
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
