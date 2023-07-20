#!/bin/bash

if [ -n "$CI_COMMIT_TAG" ] && [ -z "$RUBY_PACKAGE_VERSION" ]; then
  RUBY_PACKAGE_VERSION=${CI_COMMIT_TAG##v}
fi

source common_build_functions.sh

chmod a+r -R ../vendor/*

fpm_wrapper "datadog-apm-library-ruby" "$RUBY_PACKAGE_VERSION" \
 --input-type dir \
 --url "https://github.com/DataDog/dd-trace-rb" \
 --description "Datadog APM client library for Ruby" \
 --license "BSD-3-Clause" \
 --chdir=../vendor \
 --prefix "$LIBRARIES_INSTALL_BASE/ruby" \
 .=.
