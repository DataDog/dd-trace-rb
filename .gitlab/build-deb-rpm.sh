#!/bin/bash


echo -n "$RUBY_PACKAGE_VERSION" > auto_inject-ruby.version

source common_build_functions.sh

chmod a+r -R ../tmp/*

fpm_wrapper "datadog-apm-library-ruby" "$RUBY_PACKAGE_VERSION" \
 --input-type dir \
 --url "https://github.com/DataDog/dd-trace-rb" \
 --description "Datadog APM client library for Ruby" \
 --license "BSD-3-Clause" \
 --chdir=../tmp \
 --prefix "$LIBRARIES_INSTALL_BASE/ruby" \
 .=.
