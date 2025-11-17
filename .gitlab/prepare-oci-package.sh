#!/usr/bin/env bash

## This script is called by `package-oci` in `one-pipeline.yml`

set -euo pipefail

## Early checks

if [[ "$OS" != "linux" ]]; then
  echo "Only linux packages are supported. Exiting"
  exit 0
fi

## Obtain injector source

injector_repo="https://github.com/DataDog/datadog-injector-rb.git"
injector_ref="v1.1.0"
injector_path="${HOME}/datadog-injector-rb"

git clone "${injector_repo}" --branch "${injector_ref}" "${injector_path}"

## Prepare package structure as expected by shared pipeline

mkdir sources

# Copy injector runtime source
cp -Rv "${injector_path}/src"/* sources

# host injection expects a specific name
ln -rs sources/injector.rb sources/host_inject.rb

# Kubernetes injection expects a specific name
ln -rs sources/injector.rb sources/auto_inject.rb

## Copy system injector rules

cp ../lib-injection/requirements.json sources/requirements.json

## Copy arch-specific content, a.k.a per-version `GEM_HOME`

cp -r "../tmp/${ARCH}"/* sources

## Add `datadog` gem version information

cp ../tmp/version sources
