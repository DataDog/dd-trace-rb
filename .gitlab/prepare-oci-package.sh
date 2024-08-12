#!/bin/bash

set -e

mkdir sources

cp ../lib-injection/host_inject.rb sources
# Kubernetes injection expects a different path
ln -rs sources/host_inject.rb sources/auto_inject.rb

cp -r ../tmp/${ARCH}/* sources

cp ../tmp/version sources
