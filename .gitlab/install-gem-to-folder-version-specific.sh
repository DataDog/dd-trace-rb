#!/bin/bash

cd WIP

# TODO: Remove patch version from version string
mkdir -p $RUBY_VERSION
gem install --file Gemfile --install-dir $RUBY_VERSION --no-document --verbose
