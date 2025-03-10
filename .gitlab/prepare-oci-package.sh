#!/bin/bash

set -e

if [ "$OS" != "linux" ]; then
  echo "Only linux packages are supported. Exiting"
  exit 0
fi

mkdir sources

cp ../lib-injection/host_inject.rb sources
cp ../lib-injection/host_inject_main.rb sources
cp ../lib-injection/requirements.json sources/requirements.json
# Kubernetes injection expects a different path
ln -rs sources/host_inject.rb sources/auto_inject.rb

cp -r ../tmp/${ARCH}/* sources

cp ../tmp/version sources
