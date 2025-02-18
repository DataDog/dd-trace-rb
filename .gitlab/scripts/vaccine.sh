#!/usr/bin/env bash

set -euo pipefail

### Secret redaction utilities

__SECRETS=()

# add secret(s) to known secrets
secret_add() {
    __SECRETS+=("$@")
}

# redact all known secrets
# shellcheck disable=SC2120
secret_redact() {
    local redact="${1:-REDACTED}"
    local args=()

    local redact_escaped
    redact_escaped="$(printf '%s\n' "${redact}" | sed -e 's/[\/&]/\\&/g')"

    for secret in "${__SECRETS[@]}"; do
        # escape sed pattern characters
        local secret_escaped
        secret_escaped="$(printf '%s\n' "${secret}" | sed -e 's/[]\/$*.^[]/\\&/g')"

        # build sed arg list
        args+=(-e "s^${secret_escaped}^${redact_escaped}^gi")
    done

    # perform replacement
    sed "${args[@]}"
}

# redirect whole script output to be redacted
# must be used only after all secrets are known
secret_redir_redact() {
    exec > >(secret_redact) 2> >(secret_redact 1>&2)
}

# log safely
log() {
    printf "%s\n" "$*" | secret_redact 1>&2
}

# run safely
run() {
    "$@" > >(secret_redact) 2> >(secret_redact 1>&2)
}

# run command with safe logging
log_and_run() {
    local cmd=( "$@" )

    (
      printf '* Command:'
      for e in "${cmd[@]}"; do
        printf " "
        printf -v quoted "%q" "${e}"
        if [[ "${quoted}" == "${e}" ]]; then
            printf "%s" "${e}"
        else
            printf "%s" "'${e//'/\"'\"}'"
        fi
      done
      printf "\n"
    ) | secret_redact 1>&2

    run "${cmd[@]}"
}

# obtain GitHub vaccine token from vault
get_vaccine_token() {
    vault kv get -field=vaccine-token kv/k8s/gitlab-runner/dd-trace-rb/github-token
}

# get current commit SHA
head_commit_sha() {
    git rev-parse HEAD
}

# perform a GET request on GitHub REST API
#
# status is emitted as last line
github_api_get() {
    local token="$1"
    local repo="$2"
    local endpoint="$3"
    shift 3
    local params=("$@")

    local cmd=(
      curl
      -s
      -H "Accept: application/vnd.github.v3+json"
      -H "Authorization: token ${token}"
      -w "\n%{http_code}\n"
    )

    if [[ "${#params[@]}" -gt 0 ]]; then
        cmd+=(-G)
    fi

    for param in "${params[@]}"; do
        cmd+=(-d "${param}")
    done

    cmd+=(
      "https://api.github.com/repos/${repo}/${endpoint}"
    )

    log_and_run "${cmd[@]}"
}

# perform a POST request on GitHub REST API
#
# status is emitted as last line
github_api_post() {
    local token="$1"
    local repo="$2"
    local endpoint="$3"
    local body="$4"

    local cmd=(
      curl
      -s
      -X POST
      -H "Accept: application/vnd.github.v3+json"
      -H "Authorization: token ${token}"
      -w "\n%{http_code}\n"
    )
    cmd+=(
      -d "${body}"
    )
    cmd+=(

      "https://api.github.com/repos/${repo}/${endpoint}"
    )

    log_and_run "${cmd[@]}"
}

# dispatch a workflow
github_workflow_dispatch() {
    local token="$1"
    local repo="$2"
    local ref="$3"
    local workflow="$4"
    local inputs="$5"

    github_api_post "${token}" "${repo}" \
        "actions/workflows/${workflow}/dispatches" \
        '{"ref":"'"${ref}"'", "inputs": '"${inputs}"'}'
}

# list workflow runs
github_workflow_runs() {
    local token="$1"
    local repo="$2"
    local ref="$3"
    local workflow="$4"
    shift 4
    local params=("$@")

    github_api_get "${token}" "${repo}" \
        "actions/workflows/${workflow}/runs" \
        "${params[@]}"
}

# query a workflow run
github_workflow_run() {
    local token="$1"
    local repo="$2"
    local id="$3"
    shift 3
    local params=("$@")

    github_api_get "${token}" "${repo}" \
        "actions/runs/${id}" \
        "${params[@]}"
}

# check request status
#
# - check last line as being expected status
# - pass response body (without status) only if condition is satisfied
check_status() {
    local status="$1"

    local body
    local res
    body="$(cat)"
    res="$(printf "%s" "${body}" | tail -n1)"

    if [[ "${res}" == "${status}" ]]; then
        printf "%s" "${body}" | sed -e '$d'
    else
        log "*** Error: unexpected status ${res}"
        log "*** BODY START"
        log "${body}"
        log "*** BODY END"
    fi
}

# dispatch vaccine workflow
dispatch_workflow() {
    local vaccine_github_token="$1"
    local vaccine_ref="$2"
    local ddtrace_commit_sha="$3"
    local trigger_id="${4:-}"

    local vaccine_repo='DataDog/vaccine'
    local vaccine_workflow='vaccine.yml'

    log "*** Trigger workflow ${vaccine_workflow} at ${vaccine_repo}@${vaccine_ref} for dd-trace-rb@${ddtrace_commit_sha}${trigger_id+ "triggered by ${trigger_id}"}"
    github_workflow_dispatch "${vaccine_github_token}" "${vaccine_repo}" "${vaccine_ref}" "${vaccine_workflow}" '{"dd-lib-ruby-init-tag": "'"${ddtrace_commit_sha}"'", "trigger-id": "'"${trigger_id}"'"}' | check_status 204
}

# search for vaccine workflow run
search_workflow_run() {
    local vaccine_github_token="$1"
    local vaccine_ref="$2"
    local ddtrace_commit_sha="$3"
    local trigger_id="${4:-}"

    local vaccine_repo='DataDog/vaccine'
    local vaccine_workflow='vaccine.yml'
    local name="dd-lib-ruby-init:${ddtrace_commit_sha}${trigger_id+" ${trigger_id}"}"

    log "*** Search runs for workflow ${vaccine_workflow} at ${vaccine_repo}@${vaccine_ref} for dd-trace-rb@${ddtrace_commit_sha}${trigger_id+ "triggered by ${trigger_id}"}"
    github_workflow_runs "${vaccine_github_token}" "${vaccine_repo}" "${vaccine_ref}" "${vaccine_workflow}" 'event=workflow_dispatch' 'per_page=10' \
        | check_status 200 \
        | workflow_runs \
        | select_by name "${name}" \
        | useful_run_keys \
        | workflow_run_id \
        | head -1
}

# extract workflow runs
workflow_runs() {
    jq '.workflow_runs[]'
}

# filter by key + value
select_by() {
    local key="$1"
    local value="$2"

    jq 'select(.'"${key}"'=="'"${value}"'")'
}

# reduce output to useful keys
useful_run_keys() {
    jq '{id: .id, workflow_id: .workflow_id, event: .event, name: .name, display_title: .display_title, run_number: .run_number, run_attempt: .run_attempt, url: .url, html_url: .html_url, created_at: .created_at, status: .status, conclusion: .conclusion}'
}

# get workflow id
workflow_run_id() {
    jq -r '.id'
}

# query workflow run with a command
poll_workflow_run() {
    local vaccine_github_token="$1"
    local vaccine_poll_interval="$2"
    local workflow_run_id="$3"
    shift 3
    local cmd=("$@")

    local vaccine_repo='DataDog/vaccine'

    github_workflow_run "${vaccine_github_token}" "${vaccine_repo}" "${workflow_run_id}" \
        | check_status 200 \
        | useful_run_keys \
        | "${cmd[@]}"
}

# select completed workflows
workflow_completed() {
    jq 'select(.status == "completed")'
}

# test if workflow is successful
workflow_successful() {
    jq -e 'select(.status == "completed" and .conclusion == "success")'
}

# main entrypoint
main() {
    local vaccine_repo
    local vaccine_ref
    local vaccine_workflow
    local vaccine_github_token
    local vaccine_poll_interval
    local ddtrace_commit_sha
    local trigger_id

    vaccine_repo='DataDog/vaccine'
    vaccine_ref="${1:-master}"
    ddtrace_commit_sha="${2:-"${CI_COMMIT_SHA:-"$(head_commit_sha)"}"}"
    trigger_id="${3:-}"
    vaccine_poll_interval="10" # seconds

    vaccine_github_token="$(get_vaccine_token)"
    secret_add "${vaccine_github_token}"

  # secret_redir_redact

    dispatch_workflow "${vaccine_github_token}" "${vaccine_ref}" "${ddtrace_commit_sha}" "${trigger_id}"

    while true; do
        log "*** Waiting ${vaccine_poll_interval}s"
        sleep ${vaccine_poll_interval}

        local run_id
        run_id="$(search_workflow_run "${vaccine_github_token}" "${vaccine_ref}" "${ddtrace_commit_sha}" "${trigger_id}")"

        if [[ -z "${run_id}" ]]; then
            continue
        fi

        log "*** Found workflow run id ${run_id}"
        log "*** See: https://github.com/${vaccine_repo}/actions/runs/${run_id}"

        while true; do
            completed="$(poll_workflow_run "${vaccine_github_token}" "${vaccine_poll_interval}" "${run_id}" workflow_completed)"

            if [[ -n "${completed}" ]]; then
                if printf "%s\n" "${completed}" | workflow_successful; then
                    log "*** Workflow run successful"
                    log "*** See: https://github.com/${vaccine_repo}/actions/runs/${run_id}"
                    exit 0
                else
                    log "*** Workflow run failed"
                    log "*** WORKFLOW RUN START"
                    log "${completed}"
                    log "*** WORKFLOW RUN END"
                    log "*** See: https://github.com/${vaccine_repo}/actions/runs/${run_id}"
                    exit 1
                fi
            fi

            log "*** Waiting ${vaccine_poll_interval}s to poll again"
            sleep "${vaccine_poll_interval}"
        done
    done

}

# call main only if directly executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
