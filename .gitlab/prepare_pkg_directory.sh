#!/bin/bash

set -e

if [ -n "$CI_COMMIT_TAG" ] && [ -z "$RUBY_PACKAGE_VERSION" ]; then
  RUBY_PACKAGE_VERSION=${CI_COMMIT_TAG##v}
fi

mkdir -p pkg
cat > Gemfile << EOF
    source "https://rubygems.org"

    gem 'ddtrace', "$RUBY_PACKAGE_VERSION"
EOF

bundle lock

cp Gemfile pkg
cp Gemfile.lock pkg
cp .gitlab/install_ddtrace_deps.rb pkg
cp lib-injection/host_inject.rb pkg
