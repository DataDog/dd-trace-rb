#!/usr/bin/env bash

# This script is heavily based on registry.ddbuild.io/images/benchmarking-platform-tools-ubuntu:latest
# See https://github.com/DataDog/benchmarking-platform-tools/blob/85af849a76ce17330170e972102c391bb2e7da73/images/base/ubuntu/Dockerfile

# This is necessary because DD_TRACE_RB_BASE_IMAGE and benchmarking-platform-tools-ubuntu:latest are based on different distributions.
# Therefore, we need to install the benchmarking-platform-tools apps manually.

set -ex

# Create a dir for benchmarking-platform-tools apps
mkdir -p /app/

if [ -z "$BP_INSTALL_BRANCH" ]; then
   echo "ERROR: Make sure BP_INSTALL_BRANCH is set!"
   exit 1
fi

if [ -z "$CI_JOB_TOKEN" ]; then
   echo "ERROR: Make sure CI_JOB_TOKEN is set!"
   exit 1
fi

# Clone benchmarking-platform-tools using GitLab token and install bp-install
git clone --branch "$BP_INSTALL_BRANCH" --single-branch https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.ddbuild.io/DataDog/benchmarking-platform-tools /tmp/benchmarking-platform-tools

cp /tmp/benchmarking-platform-tools/images/templates/linux/bp-install /app/bp-install

chmod +x /app/bp-install

# Install tools using bp-install
bp-install benchmark-analyzer github-tools bp-runner

# Verify bp-runner and benchmark_analyzer work
bp-runner --version && benchmark_analyzer --version
