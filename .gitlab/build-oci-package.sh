#!/bin/bash

set -e

mkdir sources

cp -r ../tmp sources

echo -n "$RUBY_PACKAGE_VERSION" > sources/version

datadog-package create \
  --version="$RUBY_PACKAGE_VERSION" \
  --package="datadog-apm-library-rb" \
  --archive=true \
  --archive-path="datadog-apm-library-rb-$RUBY_PACKAGE_VERSION-$ARCH.tar" \
  --arch "$ARCH" \
  --os "linux" \
  ./sources
