#!/bin/bash


echo -n "$RUBY_PACKAGE_VERSION" > auto_inject-ruby.version

source common_build_functions.sh

# The normal settings for /tmp are 1777, which ls shows as drwxrwxrwt. That is wide open.
#
# This gives all users read access, and removes write access for group and others,
# to all files and directories in the tmp directory.
chmod -R a+r,go-w ../tmp/*

fpm_wrapper "datadog-apm-library-ruby" "$RUBY_PACKAGE_VERSION" \
 --input-type dir \
 --url "https://github.com/DataDog/dd-trace-rb" \
 --description "Datadog APM client library for Ruby" \
 --license "BSD-3-Clause" \
 --chdir=../tmp \
 --prefix "$LIBRARIES_INSTALL_BASE/ruby" \
 .=.
