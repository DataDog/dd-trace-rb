#!/bin/bash

set -e

mkdir sources

cp ../lib-injection/host_inject.rb sources
sed -i "s#/opt/datadog/apm/library/ruby/#/opt/datadog-packages/datadog-apm-library-ruby/$RUBY_PACKAGE_VERSION/#g" sources/host_inject.rb

cp -r ../tmp/${ARCH}/* sources

cp ../tmp/version.txt sources/version
