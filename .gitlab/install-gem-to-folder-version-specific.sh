#!/bin/bash

cd vendor

export INSTALL_DDTRACE_NATIVE_DEPS=true
ruby install_ddtrace_deps.rb
