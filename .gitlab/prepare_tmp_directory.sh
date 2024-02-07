#!/bin/bash

set -e

cd tmp
cat > Gemfile << EOF
    source "https://rubygems.org"

    gem 'ddtrace', "$RUBY_PACKAGE_VERSION", path: '../'
EOF

bundle lock

cp ../lib-injection/host_inject.rb .

cd ..
