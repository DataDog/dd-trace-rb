// This script runs in the context of `actions/github-script` from GitHub Action workflow.
// It checks the commit status of a commit (SHA).
// It fails the workflow if the combined status is not 'success'.

// API:
// - https://docs.github.com/en/rest/commits/statuses?apiVersion=2022-11-28#get-the-combined-status-for-a-specific-reference
module.exports = async ({github, context, core}) => {
  const { data: combinedStatus } = await github.rest.repos.getCombinedStatusForRef({
    owner: context.repo.owner,
    repo: context.repo.repo,
    ref: context.sha
  });

  if (combinedStatus.state !== 'success') {
    const allStatuses = await github.paginate(github.rest.repos.listCommitStatusesForRef, {
      owner: context.repo.owner,
      repo: context.repo.repo,
      ref: context.sha,
      per_page: 100
    });

    console.log(`Found ${allStatuses.length} commit statuses`);

    const failedStatuses = allStatuses.filter(s => s.state !== 'success');

    if (failedStatuses.length > 0) {
      console.log(`Found ${failedStatuses.length} failed commit statuses`);
      failedStatuses.forEach(failedStatus => {
        const message = JSON.stringify({
          context: failedStatus.context,
          state: failedStatus.state,
          url: failedStatus.target_url
        }, null, 2);

        core.error(message);
      });
    }

    core.setFailed(`Commit status is ${combinedStatus.state} with ${failedStatuses.length} failed checks`);
  }
}
