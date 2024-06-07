#!/bin/bash

set -e

mkdir sources

cp -r ../tmp/* sources
sed -i "s#/opt/datadog/apm/library/ruby/#/opt/datadog-packages/datadog-apm-library-ruby/$RUBY_PACKAGE_VERSION/#g" sources/host_inject.rb

echo -n "$RUBY_PACKAGE_VERSION" > sources/version

datadog-package create \
  --version="$RUBY_PACKAGE_VERSION" \
  --package="datadog-apm-library-ruby" \
  --archive=true \
  --archive-path="datadog-apm-library-ruby-$RUBY_PACKAGE_VERSION-$ARCH.tar" \
  --arch "$ARCH" \
  --os "linux" \
  ./sources
