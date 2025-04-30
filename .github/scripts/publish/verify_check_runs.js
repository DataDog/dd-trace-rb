// This script runs in the context of `actions/github-script` from GitHub Action workflow.
// It checks the conclusion for check suites of a commit (SHA) from a specifc Github App.
// It fails the workflow if any of the check suites are not 'success', 'neutral' or 'skipped'.

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
    const failedChecks = failedChecksArrays.flat();

    console.log(`Found a total of ${failedChecks.length} failed check runs`);

    failedChecks.forEach(failedCheck => {
      const { name, conclusion, html_url } = failedCheck;
      const message = JSON.stringify({ name, conclusion, url: html_url }, null, 2);

      core.error(message);
    });

    // Set job failure
    core.setFailed(`Found ${failedSuites.length} failed check suites`);
  }
}
