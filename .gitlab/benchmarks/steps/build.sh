#!/usr/bin/env bash

# Shallow clone a single commit
mkdir dd-trace-rb && \
  git init && \
  git remote add origin https://github.com/DataDog/dd-trace-rb.git && \
  git fetch origin --depth=1 $LATEST_COMMIT_ID && \
  git reset --hard FETCH_HEAD && \
  bundle install && \
  bundle exec rake compile