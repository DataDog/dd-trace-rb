#!/bin/sh

# This script is used by the admission controller to install the library from the
# init container into the application container.
cp auto_inject.rb "$1/auto_inject.rb"
