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
injector_ref="v1.2.1"
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

## List sources content

find sources

## Some packages we know are Ruby version-independent; let's store them once only

mkdir -p sources/ruby/common/gems

for package in libdatadog libddwaf; do
    echo ".. scanning for ${package}"

    ls -1d sources/ruby/*/gems/${package}-* | while read -r orig; do
        dest="sources/ruby/common/gems/${orig##*/}"
        if [[ -e "${dest}" ]]; then
            echo "found ${dest}; removing ${orig}"
            rm -rf "${orig}"
        else
            mv -vf "${orig}" "${dest}"
        fi
        ln -svf "${dest}" "${orig}"
    done
done

## List sources content

find sources
