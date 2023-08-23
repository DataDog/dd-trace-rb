#!/bin/bash

if [ -n "$CI_COMMIT_TAG" ] && [ -z "$RUBY_PACKAGE_VERSION" ]; then
  RUBY_PACKAGE_VERSION=${CI_COMMIT_TAG##v}
fi

echo -n "$RUBY_PACKAGE_VERSION" > auto_inject-ruby.version

source common_build_functions.sh

chmod a+r -R ../pkg/*

fpm_wrapper "datadog-apm-library-ruby" "$RUBY_PACKAGE_VERSION" \
 --input-type dir \
 --url "https://github.com/DataDog/dd-trace-rb" \
 --description "Datadog APM client library for Ruby" \
 --license "BSD-3-Clause" \
 --chdir=../pkg \
 --prefix "$LIBRARIES_INSTALL_BASE/ruby" \
 .=.
