#!/usr/bin/env bash
# usage: run.sh <baseline|apm-only|apm+dsm> [slug]
#
# Runs run_timeit.rb with this folder's bundle (Gemfile; Gemfile.tracer for the tracer scenarios), against
# the datadog gem of the repo checkout containing this script (so it works from any worktree).
# Env overrides: see README.md.
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

export EXPERIMENT_NAME=${EXPERIMENT_NAME:-$NAME}
export KAFKA_TOPIC=${KAFKA_TOPIC:-benchmark-topic-ruby-$NAME-$SLUG}
export TIMEIT_OUTPUT=${TIMEIT_OUTPUT:-$OUT_DIR/ruby-$SLUG.$NAME.json}
# Must accept payloads: a dead port adds connection-error overhead to the tracer scenarios (see README).
export DD_TRACE_AGENT_URL=${DD_TRACE_AGENT_URL:-http://127.0.0.1:18127}

case $SCENARIO in
  baseline) unset ENABLE_TRACER DD_DATA_STREAMS_ENABLED ;;
  apm-only) export ENABLE_TRACER=true DD_DATA_STREAMS_ENABLED=false ;;
  apm+dsm) export ENABLE_TRACER=true DD_DATA_STREAMS_ENABLED=true ;;
esac

if [ "${ENABLE_TRACER:-}" = true ]; then
  # The path gem's version and dependencies follow the checkout, so its lockfile can't be committed:
  # derive it from Gemfile.lock and check that the shared gems kept their locked versions.
  export BUNDLE_GEMFILE=$PWD/Gemfile.tracer
  cp Gemfile.lock Gemfile.tracer.lock
  bundle lock
  ruby -rbundler -e '
    locked = ->(file) { Bundler::LockfileParser.new(File.read(file)).specs.map { |s| [s.name, s.version.to_s] }.to_h }
    tracer = locked.call("Gemfile.tracer.lock")
    changed = locked.call("Gemfile.lock").reject { |name, version| tracer[name] == version }
    abort("Gemfile.tracer.lock changed shared gems: #{changed.keys.join(", ")}") unless changed.empty?'
else
  export BUNDLE_GEMFILE=$PWD/Gemfile
fi
BUNDLE_FROZEN=true bundle install --quiet

if [ "${ENABLE_TRACER:-}" = true ]; then
  # Bundler doesn't build path gems' native extensions. Build libdatadog_api (DSM needs it for
  # DDSketch) out of tree, as `gem install` would, and fail if it isn't built or doesn't load.
  BUILD_DIR=$TRACER_ROOT/tmp/kafka_dsm/libdatadog_api
  SO_FILE=$(ruby -e 'print "libdatadog_api.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}.so"')
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"
  # A skipped build may exit non-zero, exit 0 without a Makefile, or leave a no-op Makefile: check the result.
  (cd "$BUILD_DIR" && DD_FAIL_INSTALL_IF_MISSING_EXTENSION=true bundle exec ruby "$TRACER_ROOT/ext/libdatadog_api/extconf.rb" &&
    make) || true
  if [ ! -f "$BUILD_DIR/$SO_FILE" ]; then
    echo "libdatadog_api was not built: extconf.rb skipped it or the build failed (see the WARN/errors above and $BUILD_DIR/mkmf.log)" >&2
    exit 1
  fi
  cp "$BUILD_DIR/$SO_FILE" "$TRACER_ROOT/lib/"
  bundle exec ruby -e 'require "datadog"; f = Datadog::Core::LIBDATADOG_API_FAILURE; abort("libdatadog_api failed to load: #{f}") if f'
  bundle exec ruby -e 'require "datadog/version"; puts "datadog gem version: #{Datadog::VERSION::STRING}"'
fi

exec bundle exec ruby run_timeit.rb
