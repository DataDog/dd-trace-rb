require 'spec_helper'
require 'datadog/symbol_database/component'
require 'datadog/symbol_database/logger'
require 'datadog/core/configuration'
require 'logger'

# Deterministic reproducer for the Ruby 2.6 `logger boom` flake observed
# under `spec:main[--seed 5627]` with CI env vars
# (see PR #5798, handoff-pr5798-ruby26-logger-boom-flake-rootcause.md).
#
# The bug is cross-version (not 2.6-specific): the failing test
# `does not propagate exceptions when logger.debug itself raises` covers
# the hot-load hook callback only, but `allow(raw_logger).to
# receive(:debug).and_raise(...)` is process-wide. The scheduler thread's
# `@logger.debug` calls in `extract_and_upload` (line 500), its rescue
# handler (line 511), and `scheduler_loop`'s rescue handler (line 458)
# have no inner rescue. When `raw_logger.debug` raises while the
# scheduler is inside `extract_and_upload`, the exception terminates the
# scheduler thread. `component.shutdown!` then calls
# `@scheduler_thread&.join(5)`, and `Thread#join` re-raises the
# unhandled exception in the test thread, surfacing as the example
# failure with the scheduler thread's backtrace.
#
# This reproducer forces the timing race deterministically by holding
# the scheduler thread inside `extract_all` on a Queue, then activating
# the stub before releasing it.
RSpec.describe 'SymDB scheduler logger boom reproducer' do
  let(:settings) do
    s = Datadog::Core::Configuration::Settings.new
    s.symbol_database.enabled = true
    s.symbol_database.internal.force_upload = true
    s
  end
  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver.call(settings)
  end
  let(:raw_logger) { instance_double(Logger, debug: nil, warn: nil) }
  let(:logger) { Datadog::SymbolDatabase::Logger.new(settings, raw_logger) }

  before do
    # Skip the 5-second debounce so the scheduler enters extract_and_upload
    # immediately on signal.
    stub_const('Datadog::SymbolDatabase::Component::EXTRACT_DEBOUNCE_INTERVAL', 0)
    # No-op the upload network path.
    allow_any_instance_of(Datadog::SymbolDatabase::ScopeBatcher).to receive(:add_scope)
    allow_any_instance_of(Datadog::SymbolDatabase::ScopeBatcher).to receive(:flush)
    allow_any_instance_of(Datadog::SymbolDatabase::ScopeBatcher).to receive(:shutdown)
    hide_const('ActiveSupport')
    hide_const('Rails::Railtie')
  end

  it 'shutdown! does not propagate logger exceptions from the scheduler thread' do
    entered_extract = Queue.new
    resume_extract = Queue.new

    # Hold the scheduler thread inside extract_all so we can flip the
    # raw_logger.debug stub before the scheduler reaches `@logger.debug`
    # at the success-path log line in extract_and_upload.
    allow_any_instance_of(Datadog::SymbolDatabase::Extractor).to receive(:extract_all) do
      entered_extract.push(:in)
      resume_extract.pop
    end

    component = Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger)

    # Wait for the scheduler to enter extract_all.
    Timeout.timeout(5) { entered_extract.pop }

    # Stub raw_logger.debug to raise. The scheduler is blocked inside
    # extract_all and has not yet reached its post-extraction debug log.
    allow(raw_logger).to receive(:debug).and_raise(RuntimeError.new('logger boom'))

    # Release extract_all. The scheduler proceeds to the success-path
    # `@logger.debug { "symdb: initial extracted ..." }` call, which now
    # raises through the wrapped Forwardable chain.
    resume_extract.push(:go)

    # `shutdown!` invokes `@scheduler_thread&.join(5)`. Without the fix,
    # the scheduler thread has terminated with the unhandled `logger boom`
    # exception, and `Thread#join` re-raises it here.
    expect { component.shutdown! }.not_to raise_error
  end
end
