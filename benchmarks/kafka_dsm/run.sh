#!/usr/bin/env bash
# usage: run.sh <baseline|apm-only|apm+dsm> [slug]
#
# Runs run_timeit.rb with this folder's Gemfile, against the datadog gem of the repo checkout
# containing this script (so it works from any worktree). Env overrides: see README.md.
set -euo pipefail
cd "$(dirname "$0")"

SCENARIO=${1:?usage: run.sh <baseline|apm-only|apm+dsm> [slug]}
SLUG=${2:-base}
case $SCENARIO in
  baseline|apm-only|apm+dsm) ;;
  *) echo "unknown scenario: $SCENARIO" >&2; exit 2 ;;
esac
# File/topic-safe scenario slug: apm+dsm -> apm-plus-dsm.
NAME=${SCENARIO//+/-plus-}
OUT_DIR=${OUT_DIR:-$PWD/out}
mkdir -p "$OUT_DIR"
TRACER_ROOT=$(cd ../.. && pwd)

export KAFKA_TOPIC=${KAFKA_TOPIC:-benchmark-topic-ruby-$NAME-$SLUG}
export TIMEIT_OUTPUT=${TIMEIT_OUTPUT:-$OUT_DIR/ruby-$SLUG.$NAME.json}
# Must accept payloads: a dead port adds connection-error overhead to the tracer scenarios (see README).
export DD_TRACE_AGENT_URL=${DD_TRACE_AGENT_URL:-http://127.0.0.1:18127}

case $SCENARIO in
  baseline) unset ENABLE_TRACER DD_DATA_STREAMS_ENABLED ;;
  apm-only) export ENABLE_TRACER=true DD_DATA_STREAMS_ENABLED=false ;;
  apm+dsm) export ENABLE_TRACER=true DD_DATA_STREAMS_ENABLED=true ;;
esac

# The Gemfile depends on ENABLE_TRACER (baseline has no datadog gem), so resolve it on every run.
export BUNDLE_GEMFILE=$PWD/Gemfile
rm -f Gemfile.lock
bundle install --quiet

if [ "${ENABLE_TRACER:-}" = true ]; then
  # Bundler doesn't build path gems' native extensions. Build libdatadog_api (DSM needs it for
  # DDSketch) out of tree, as `gem install` would, and fail if it doesn't load.
  BUILD_DIR=$TRACER_ROOT/tmp/kafka_dsm/libdatadog_api
  mkdir -p "$BUILD_DIR"
  (cd "$BUILD_DIR" && DD_FAIL_INSTALL_IF_MISSING_EXTENSION=true bundle exec ruby "$TRACER_ROOT/ext/libdatadog_api/extconf.rb" && make)
  cp "$BUILD_DIR"/libdatadog_api.*.so "$TRACER_ROOT/lib/"
  bundle exec ruby -e 'require "datadog"; f = Datadog::Core::LIBDATADOG_API_FAILURE; abort("libdatadog_api failed to load: #{f}") if f'
  bundle exec ruby -e 'require "datadog/version"; puts "datadog gem version: #{Datadog::VERSION::STRING}"'
fi

exec bundle exec ruby run_timeit.rb
