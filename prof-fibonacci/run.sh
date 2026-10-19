#!/bin/bash

set -euo pipefail

#IFS=':' read -r DD_AGENT_HOST DD_TRACE_AGENT_PORT <<< "$TRACE_AGENT_URL"

# export DD_AGENT_HOST
# export DD_TRACE_AGENT_PORT
export DD_SERVICE=ivoanjo-testing-wip #prof-fibonacci-miteruby
export DD_PROFILING_ENABLED=true
export DD_PROFILING_ALLOCATION_ENABLED=false
export DD_PROFILING_EXPERIMENTAL_HEAP_ENABLED=false # enable heap profiling, still alpha at the time of this writing
export DD_PROFILING_EXPERIMENTAL_HEAP_SIZE_ENABLED=false # enable heap size profiling, still alpha at the time of this writing
export DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true # show classes in profile, new feature being tested
export DD_PROFILING_SIGHANDLER_SAMPLING_ENABLED=true
export RUBY_YJIT_ENABLE=true

ruby -v

exec bundle exec ddprofrb exec rackup -p 8080 -q
