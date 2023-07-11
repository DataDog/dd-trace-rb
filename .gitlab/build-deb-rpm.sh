#!/bin/bash

if [ -n "$CI_COMMIT_TAG" ] && [ -z "$RUBY_PACKAGE_VERSION" ]; then
  RUBY_PACKAGE_VERSION=${CI_COMMIT_TAG##v}
fi

source common_build_functions.sh

# Get a list of directories with the "-static" suffix
directories=($(find ../vendor -maxdepth 4 -type d -name "*-static"))

# Check if any directories were found
if [ ${#directories[@]} -eq 0 ]; then
  echo "No directories with the '-static' suffix found."
  exit 1
fi

# Loop through the directories
for dir in "${directories[@]}"; do
  # Remove the "./" prefix and the "-static" suffix from the directory name
  new_dir="${dir#./}"
  new_dir="${new_dir%-static}"
  # Rename the directory
  mv "$dir" "$new_dir"
  echo "Directory '$dir' renamed to '$new_dir'."
done

# Not sure how it is called
fpm_wrapper "datadog-apm-library-ruby" "$RUBY_PACKAGE_VERSION" \
 --input-type dir \
 --url "https://github.com/DataDog/dd-trace-rb" \
 --description "Datadog APM client library for Ruby" \
 --license "BSD-3-Clause" \
 --chdir=../vendor \
 --prefix "$LIBRARIES_INSTALL_BASE/ruby" \
 .=.
