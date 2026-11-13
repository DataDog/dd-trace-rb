ARG DD_TRACE_RB_BASE_IMAGE=registry.ddbuild.io/ci/benchmarking-platform:dd-trace-rb-base

# Base image providing Ruby environment and dd-trace-rb dependencies.
# Built from dd-trace-rb/benchmarks/Dockerfile during the build-ci-images job.
# See .gitlab-ci.yml for the full build chain.
FROM ${DD_TRACE_RB_BASE_IMAGE}

ARG CI_JOB_TOKEN
ARG BP_INSTALL_BRANCH
ENV BP_INSTALL_BRANCH=${BP_INSTALL_BRANCH:-"main"}
ENV CI_JOB_TOKEN=${CI_JOB_TOKEN}

ENV PYENV_ROOT="/pyenv"
ENV PATH="$PYENV_ROOT/shims:$PYENV_ROOT/bin:/app:/app/bp-runner/:/app/benchmark-github-tools/:/app/benchmark-analyzer/:/usr/local/bundle/bin:$PATH"

COPY install-base-deps.sh install-benchmarking-platform-tools.sh .
RUN ./install-base-deps.sh
RUN ./install-benchmarking-platform-tools.sh

# Clean up CI_JOB_TOKEN from environment
ENV CI_JOB_TOKEN=""

WORKDIR /data
