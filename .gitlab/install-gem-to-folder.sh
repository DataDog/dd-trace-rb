#!/bin/bash

set -e

if [ -n "$CI_COMMIT_TAG" ] && [ -z "$RUBY_PACKAGE_VERSION" ]; then
  RUBY_PACKAGE_VERSION=${CI_COMMIT_TAG##v}
fi

mkdir -p WIP
cat > Gemfile << EOF
    source "https://rubygems.org"

    gem 'ddtrace', "$RUBY_PACKAGE_VERSION"
EOF

bundle check

cp Gemfile WIP
cp Gemfile.lock WIP
cp lib-injection/host_inject.rb WIP

# gem install --file Gemfile --install-dir WIP --no-document --verbose
