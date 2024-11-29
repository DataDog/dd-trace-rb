#!/bin/bash

set -e

mkdir sources

cp ../lib-injection/host_inject.rb sources
cp ../lib-injection/host_inject_main.rb sources
cp ../lib-injection/requirements.json sources/requirements.json
# Kubernetes injection expects a different path
ln -rs sources/host_inject.rb sources/auto_inject.rb

cp -r ../tmp/${ARCH}/* sources

cp ../tmp/version sources
