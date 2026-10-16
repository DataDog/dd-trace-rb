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
injector_ref="v1.5.1"
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

## Some packages we know are Ruby version-independent; let's store them once
## only. The `datadog` gem is not: every gem home's copy carries the
## `libdatadog_api` extension compiled for its own Ruby. The `.so` name
## embeds the Ruby version, so all homes' `.so` files coexist in one shared
## copy, and the profiling extension a customer-side reinstall compiles is
## named per version too, so a shared copy cannot collide across Rubies. The
## mkmf Makefile under ext/libdatadog_api also differs per home; the shared
## copy keeps the first home's, and in-place rebuilds regenerate it.

mkdir -p sources/ruby/common/gems

for package in libdatadog libddwaf datadog-ruby_core_source logger datadog; do
    echo ".. scanning for ${package}"

    # The version anchor keeps the `datadog` entry from matching the
    # `datadog-ruby_core_source` symlinks.
    ls -1d sources/ruby/*/gems/${package}-[0-9]* | while read -r orig; do
        dest="sources/ruby/common/gems/${orig##*/}"
        if [[ -e "${dest}" ]]; then
            echo "found ${dest}; removing ${orig}"
            if [[ "${package}" == datadog ]]; then
                mv -v "${orig}"/lib/libdatadog_api.*.so "${dest}/lib/"
            fi
            rm -rf "${orig}"
        else
            mv -vf "${orig}" "${dest}"
        fi
        ln -srvf "${dest}" "${orig}"
    done
done

## Prune the `libdatadog` and `libddwaf` vendored binaries to the package
## arch: both gems select only the running platform's vendored binaries at
## runtime, so every other vendored platform dir is unreachable in this
## package.

case "${ARCH}" in
  amd64)
    package_cpu="x86_64"
    ;;
  arm64)
    package_cpu="aarch64"
    ;;
  *)
    echo "Unknown ARCH '${ARCH}' when pruning the vendor dirs. Exiting"
    exit 1
    ;;
esac

## `Libdatadog.current_platform` only ever selects the running CPU's
## `-linux` dir, or its `-linux-musl` variant through the musl fallback
## for Alpine.

for vendor_dir in sources/ruby/common/gems/libdatadog-*/vendor/libdatadog-*/; do
  if [[ ! -d "${vendor_dir}" ]]; then
    echo "No libdatadog vendor dir under sources/ruby/common/gems/. Exiting"
    exit 1
  fi

  for platform_dir in "${vendor_dir}"*/; do
    platform="${platform_dir%/}"
    platform="${platform##*/}"
    case "${platform}" in
      "${package_cpu}-linux"|"${package_cpu}-linux-musl")
        ;;
      *)
        echo "pruning ${platform_dir}"
        rm -rf "${platform_dir}"
        ;;
    esac
  done

  for platform in "${package_cpu}-linux" "${package_cpu}-linux-musl"; do
    if [[ ! -d "${vendor_dir}${platform}" ]]; then
      echo "Missing ${platform} binaries under ${vendor_dir}. Exiting"
      exit 1
    fi
  done
done

## `libddwaf`'s `shared_lib_path` loads `libddwaf-<version>-<os>-<cpu>`
## for the running platform only (`ffi_lib` takes that single path).

libddwaf_platform="linux-${package_cpu}"

for vendor_dir in sources/ruby/common/gems/libddwaf-*/vendor/libddwaf/; do
  if [[ ! -d "${vendor_dir}" ]]; then
    echo "No libddwaf vendor dir under sources/ruby/common/gems/. Exiting"
    exit 1
  fi

  found_libddwaf_platform=0
  for platform_dir in "${vendor_dir}"libddwaf-*/; do
    platform="${platform_dir%/}"
    platform="${platform##*/}"
    case "${platform}" in
      libddwaf-*-"${libddwaf_platform}")
        found_libddwaf_platform=1
        ;;
      *)
        echo "pruning ${platform_dir}"
        rm -rf "${platform_dir}"
        ;;
    esac
  done

  if [[ "${found_libddwaf_platform}" == 0 ]]; then
    echo "Missing ${libddwaf_platform} binaries under ${vendor_dir}. Exiting"
    exit 1
  fi
done
