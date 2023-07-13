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
cp .gitlab/install_ddtrace_deps.rb vendor
cp lib-injection/host_inject.rb vendor

ruby vendor/install_ddtrace_deps.rb debase-ruby_core_source libdatadog libddwaf msgpack ffi ddtrace
