#!/bin/bash

set -e

mkdir sources

cp ../lib-injection/host_inject.rb sources
# Kubernetes injection expects a different path
cp sources/host_inject.rb sources/auto_inject.rb

sed -i "s#PATH_PLACEHOLDER#/opt/datadog-packages/datadog-apm-library-ruby/${RUBY_PACKAGE_VERSION}#g" sources/host_inject.rb
sed -i "s#PATH_PLACEHOLDER#/datadog-lib#g" sources/auto_inject.rb

echo "PRINTING ALL FILES IN TMP"
ls  -lR ../tmp/${ARCH}/

cp -r ../tmp/${ARCH}/* sources

echo "PRINTING ALL FILES IN SOURCES"
ls -lR sources

cp ../tmp/version.txt sources/version
