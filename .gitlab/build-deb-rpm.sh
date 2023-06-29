#!/bin/bash

if [ -n "$CI_COMMIT_TAG" ] && [ -z "$RUBY_PACKAGE_VERSION" ]; then
  RUBY_PACKAGE_VERSION=${CI_COMMIT_TAG##v}
fi

source common_build_functions.sh

mkdir -p temp

cat > Gemfile << EOF
source "https://rubygems.org"

gem 'ddtrace', "$RUBY_PACKAGE_VERSION"
EOF

# Move to docker
apt-get update && apt-get -y install make gcc libffi-dev

# This would creates `Gemfile.lock`
gem install --file Gemfile --install-dir temp --no-document --verbose

cp Gemfile temp
cp Gemfile.lock temp
cp ../lib-injection/host_inject.rb temp

# # Not sure how it is called
# fpm_wrapper "datadog-apm-library-ruby" "$RUBY_PACKAGE_VERSION" \
#   --input-type dir \
#   --url "https://github.com/DataDog/dd-trace-rb" \
#   --description "Datadog APM client library for Ruby" \
#   --license "BSD-3-Clause" \
#   --chdir=temp \
#   --prefix "$LIBRARIES_INSTALL_BASE/ruby" \
#   .=.
