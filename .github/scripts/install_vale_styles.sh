#!/bin/bash
set -euo pipefail

# Downloads the pinned vale style packages used by the changelog checks
# into vale/styles/, mirroring the layout the .vale.ini StylePath expects.

if [[ -z "${WRITE_GOOD_VERSION:-}" || -z "${WRITE_GOOD_SHA256:-}" \
    || -z "${PROSELINT_VERSION:-}" || -z "${PROSELINT_SHA256:-}" \
    || -z "${HARPER_VERSION:-}" || -z "${HARPER_SHA256:-}" ]]; then
    echo "Error: WRITE_GOOD_VERSION, WRITE_GOOD_SHA256, PROSELINT_VERSION," \
        "PROSELINT_SHA256, HARPER_VERSION, and HARPER_SHA256 environment" \
        "variables must all be set"
    exit 1
fi

styles_dir="vale/styles"
mkdir -p "${styles_dir}"

# The write-good and proselint zips contain a single top-level directory
# named after the package, so extracting into styles_dir lands them at
# vale/styles/<package>/. The CI job containers ship without unzip, so the
# extraction uses the repo's ruby-based extractor instead.
install_package() {
    local package="$1" version="$2" sha256="$3"
    local archive="/tmp/${package}.zip"

    curl -sSL -o "${archive}" \
        "https://github.com/errata-ai/${package}/releases/download/v${version}/${package}.zip"
    echo "${sha256}  ${archive}" | sha256sum -c -
    rm -rf "${styles_dir:?}/${package}"
    ruby .github/scripts/extract_zip.rb "${archive}" "${styles_dir}"
}

install_package write-good "${WRITE_GOOD_VERSION}" "${WRITE_GOOD_SHA256}"
install_package proselint "${PROSELINT_VERSION}" "${PROSELINT_SHA256}"

# The Harper zip (github.com/vale-cli/Harper) nests its rules under
# <package>/styles/, alongside the POS-tagger dictionaries its sequence
# rules need; the dictionaries must sit at vale/styles/config/ next to
# the rules, or those rules silently match nothing.
harper_dir="$(mktemp -d)"
curl -sSL -o /tmp/Harper.zip \
    "https://github.com/vale-cli/Harper/releases/download/v${HARPER_VERSION}/Harper.zip"
echo "${HARPER_SHA256}  /tmp/Harper.zip" | sha256sum -c -
ruby .github/scripts/extract_zip.rb /tmp/Harper.zip "${harper_dir}"
rm -rf "${styles_dir:?}/Harper" "${styles_dir:?}/config"
cp -R "${harper_dir}/Harper/styles/Harper" "${styles_dir}/Harper"
cp -R "${harper_dir}/Harper/styles/config" "${styles_dir}/config"
rm -rf "${harper_dir}"
