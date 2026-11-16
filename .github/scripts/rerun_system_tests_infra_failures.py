"""Re-run System Tests jobs that failed because a GitHub-hosted runner lost
communication with GitHub.

Contract:
    Input:  GITHUB_REPOSITORY, GH_TOKEN with actions:write, RUN_ID of a
            completed failed run, DRY_RUN set to 'true' to report the decision
            without issuing a re-run.
    Output: a re-run request for infra-class failures and a decision report on
            stdout and in $GITHUB_STEP_SUMMARY.
    Failure: nonzero exit for invalid input, API errors, or a rejected re-run
            request.
"""

import json
import os
import subprocess
import sys

LOST_COMMUNICATION_ANNOTATION = "The hosted runner lost communication with the server"
FAILED_CONCLUSIONS = ("failure", "timed_out", "startup_failure")


def fail(message):
    """Print an error to stderr and exit with status 1."""
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def gh_api(endpoint, method="GET", slurp=False):
    """Request a GitHub API endpoint and return the parsed JSON response."""
    command = ["gh", "api", "--method", method]
    if slurp:
        command += ["--paginate", "--slurp"]
    command.append(endpoint)
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        fail(f"gh api {method} {endpoint} exited {result.returncode}: {result.stderr.strip()}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        fail(f"gh api {method} {endpoint} returned invalid JSON: {error}")


def report(lines):
    """Print the decision and add it to the GitHub step summary."""
    for line in lines:
        print(line)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as summary:
            for line in lines:
                summary.write(f"{line}\n")


def collect_jobs(repository, run_id):
    """Return every job of the run, following the pagination links."""
    pages = gh_api(f"repos/{repository}/actions/runs/{run_id}/jobs?per_page=100", slurp=True)
    return [job for page in pages for job in page["jobs"]]


def jobs_that_lost_communication(repository, failed_jobs):
    """Return the names of failed jobs annotated as having lost communication."""
    lost_jobs = []
    for job in failed_jobs:
        annotations = gh_api(f"repos/{repository}/check-runs/{job['id']}/annotations")
        lost = any(
            LOST_COMMUNICATION_ANNOTATION in annotation.get("message", "") for annotation in annotations
        )
        if lost:
            lost_jobs.append(job["name"])
    return lost_jobs


def request_rerun(endpoint, repository, run_id, attempt):
    """POST the re-run request and verify that the run advanced to a new attempt."""
    result = subprocess.run(
        ["gh", "api", "--method", "POST", endpoint], capture_output=True, text=True, check=False
    )
    if result.returncode == 0:
        return
    error = result.stderr.strip()
    # A re-run POST can return an error after GitHub already accepted it, so
    # check the run state before reporting the re-run as rejected.
    run = gh_api(f"repos/{repository}/actions/runs/{run_id}")
    rerun_accepted = run.get("run_attempt", 0) > attempt and run.get("status") in ("queued", "in_progress")
    if rerun_accepted:
        print(f"warning: re-run request returned an error after the run advanced: {error}")
        return
    fail(f"re-run request {endpoint} exited {result.returncode}: {error}")


def main():
    repository = os.environ.get("GITHUB_REPOSITORY")
    run_id = os.environ.get("RUN_ID")
    if not repository:
        fail("GITHUB_REPOSITORY is not set")
    if not run_id or not run_id.isdigit():
        fail("RUN_ID must be the numeric id of a System Tests run")

    dry_run = os.environ.get("DRY_RUN", "").lower() == "true"

    run = gh_api(f"repos/{repository}/actions/runs/{run_id}")
    if run.get("status") != "completed":
        fail(f"run {run_id} is not completed (status: {run.get('status')})")
    if run.get("conclusion") != "failure":
        fail(f"run {run_id} did not fail (conclusion: {run.get('conclusion')})")

    jobs = collect_jobs(repository, run_id)
    failed_jobs = [job for job in jobs if job.get("conclusion") in FAILED_CONCLUSIONS]

    lines = [f"Run {run_id} failed with conclusion 'failure'."]
    if failed_jobs:
        lost_jobs = jobs_that_lost_communication(repository, failed_jobs)
        if not lost_jobs:
            lines.append("No failed job lost communication with the server; no re-run.")
            report(lines)
            return
        lines.append(f"Jobs that lost communication: {', '.join(lost_jobs)}.")
        rerun_endpoint = f"repos/{repository}/actions/runs/{run_id}/rerun-failed-jobs"
        rerun_action = "re-run the failed jobs"
    else:
        lines.append("No failed job is recorded; GitHub lost the job records.")
        rerun_endpoint = f"repos/{repository}/actions/runs/{run_id}/rerun"
        rerun_action = "re-run all jobs"

    if dry_run:
        lines.append(f"Dry run: would {rerun_action} via {rerun_endpoint}.")
        report(lines)
        return

    request_rerun(rerun_endpoint, repository, run_id, run.get("run_attempt"))
    lines.append(f"Issued a request to {rerun_action}.")
    report(lines)


if __name__ == "__main__":
    main()
