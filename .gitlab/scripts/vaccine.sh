#!/bin/bash

set -e

GH_VACCINE_PAT=$(vault kv get -field=vaccine-token kv/k8s/gitlab-runner/dd-trace-rb/github-token)
REPO="Datadog/vaccine"
POLL_INTERVAL=60  # seconds

REF="${1:-master}"
SHA="${2:-"$(git rev-parse HEAD)"}"

# Trigger workflow
echo "Triggering workflow..."
TRIGGER_RESPONSE=$(curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_VACCINE_PAT" \
  -w "\n%{http_code}" \
  "https://api.github.com/repos/$REPO/actions/workflows/vaccine.yml/dispatches" \
  -d '{"ref":"'${REF}'", "inputs": {"commit_sha": "'$CI_COMMIT_SHA'"}}' 2>&1)

HTTP_STATUS=$(echo "$TRIGGER_RESPONSE" | tail -n1)
if [ "$HTTP_STATUS" -ne 204 ]; then
  echo "Error: Workflow trigger failed with status $HTTP_STATUS"
  echo "Response: $(echo "$TRIGGER_RESPONSE" | sed '$ d')"
  exit 1
fi

echo "Successfully triggered workflow. Waiting for workflow to start..."
sleep 5  # Give GitHub a moment to create the workflow run

# Get the most recent workflow run
echo "Fetching most recent workflow run..."
RUNS_RESPONSE=$(curl -s \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_VACCINE_PAT" \
  -w "\n%{http_code}" \
  "https://api.github.com/repos/$REPO/actions/runs?event=workflow_dispatch&per_page=1" 2>&1)

HTTP_STATUS=$(echo "$RUNS_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RUNS_RESPONSE" | sed '$ d')

if [ "$HTTP_STATUS" -ne 200 ]; then
  echo "Error: Fetching runs failed with status $HTTP_STATUS"
  echo "Response: $RESPONSE_BODY"
  exit 1
fi

# Get the most recent run ID
WORKFLOW_ID=$(echo "$RESPONSE_BODY" | jq -r '.workflow_runs[0].id')

if [ -z "$WORKFLOW_ID" ] || [ "$WORKFLOW_ID" = "null" ]; then
  echo "Error: Could not find recent workflow run"
  exit 1
fi

echo "Found workflow run ID: $WORKFLOW_ID"

# Poll workflow status
while true; do
  RUN_RESPONSE=$(curl -s \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token $GH_VACCINE_PAT" \
    -w "\n%{http_code}" \
    "https://api.github.com/repos/$REPO/actions/runs/$WORKFLOW_ID" 2>&1)

  HTTP_STATUS=$(echo "$RUN_RESPONSE" | tail -n1)
  RESPONSE_BODY=$(echo "$RUN_RESPONSE" | sed '$ d')

  if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "Error: Fetching run status failed with status $HTTP_STATUS"
    echo "Response: $RESPONSE_BODY"
    exit 1
  fi

  STATUS=$(echo "$RESPONSE_BODY" | jq -r .status)
  CONCLUSION=$(echo "$RESPONSE_BODY" | jq -r .conclusion)

  if [ "$STATUS" = "completed" ]; then
    if [ "$CONCLUSION" = "success" ]; then
      echo "✅ Workflow completed successfully!"
      exit 0
    else
      echo "❌ Workflow failed with conclusion: $CONCLUSION"
      echo "See details: https://github.com/$REPO/actions/runs/$WORKFLOW_ID"
      exit 1
    fi
  fi

  echo "Current status: $STATUS (Checking again in ${POLL_INTERVAL}s)"
  sleep $POLL_INTERVAL
done
