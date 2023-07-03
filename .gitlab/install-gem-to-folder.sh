#!/bin/bash

set -e

if [ -n "$CI_COMMIT_TAG" ] && [ -z "$RUBY_PACKAGE_VERSION" ]; then
  RUBY_PACKAGE_VERSION=${CI_COMMIT_TAG##v}
fi

mkdir -p vendor
cat > Gemfile << EOF
    source "https://rubygems.org"

    gem 'ddtrace', "$RUBY_PACKAGE_VERSION"
EOF

bundle lock

cp Gemfile vendor
cp Gemfile.lock vendor
cp install_ddtrace_deps.rb vendor
cp lib-injection/host_inject.rb vendor

export INSTALL_DDTRACE_NATIVE_DEPS=true
export INSTALL_DDTRACE_NON_NATIVE_DEPS=true

ruby install_ddtrace_deps.rb
