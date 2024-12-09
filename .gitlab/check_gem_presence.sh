#!/bin/bash
set -e

if [ -n "$CI_COMMIT_TAG" ] && [ -z "$RUBY_PACKAGE_VERSION" ]; then
  RUBY_PACKAGE_VERSION=${CI_COMMIT_TAG##v}
fi

max_attempts=60
interval=60 # Retry after 60 seconds
attempt=1

while [ $attempt -le $max_attempts ]; do
  output=$(gem search datadog  -e -v $RUBY_PACKAGE_VERSION | { grep $RUBY_PACKAGE_VERSION || :; })
  if [ -z "$output" ]
  then
    echo "Attempt ${attempt}/${max_attempts}: Not found yet."
    attempt=$((attempt + 1))
    sleep ${interval}
  else
    echo "$output found!"
    exit 0
  fi
done

echo "Max attempts reached."
exit 1
