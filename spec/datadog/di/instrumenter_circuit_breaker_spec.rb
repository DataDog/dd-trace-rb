# frozen_string_literal: true

require 'datadog/di/spec_helper'
require 'datadog/di/instrumenter'
require_relative 'hook_method'

RSpec.describe 'Datadog::DI::Instrumenter circuit breaker' do
  di_test

  let(:observed_calls) { [] }
  let(:disabled_calls) { [] }

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
    allow(settings.dynamic_instrumentation.internal).to receive(:untargeted_trace_points).and_return(false)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_depth).and_return(2)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_attribute_count).and_return(2)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_string_length).and_return(100)
    allow(settings.dynamic_instrumentation).to receive(:redacted_type_names).and_return([])
    allow(settings.dynamic_instrumentation).to receive(:redacted_identifiers).and_return([])
    allow(settings.dynamic_instrumentation).to receive(:redaction_excluded_identifiers).and_return([])
    allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(true)
    allow(settings.dynamic_instrumentation.internal).to receive(:max_processing_time).and_return(0)
  end

  let(:redactor) do
    Datadog::DI::Redactor.new(settings)
  end

  let(:serializer) do
    Datadog::DI::Serializer.new(settings, redactor)
  end

  let(:logger) do
    instance_double(Logger)
  end

  let(:instrumenter) do
    Datadog::DI::Instrumenter.new(settings, serializer, logger, code_tracker: nil)
  end

  let(:responder) do
    # Custom responder that tracks both executions and disabled callbacks
    Class.new do
      def initialize(observed_calls, disabled_calls)
        @observed_calls = observed_calls
        @disabled_calls = disabled_calls
      end

      def probe_executed_callback(context)
        @observed_calls << context
      end

      def probe_condition_evaluation_failed_callback(context, exc)
        raise "Unexpected condition failure: #{exc}"
      end

      def probe_disabled_callback(probe, duration)
        @disabled_calls << { probe: probe, duration: duration }
      end
    end.new(observed_calls, disabled_calls)
  end

  let(:probe) do
    Datadog::DI::Probe.new(
      id: 'test-probe-1',
      type: :log,
      type_name: 'HookTestClass',
      method_name: 'hook_test_method',
    )
  end

  after do
    instrumenter.unhook(probe)
  end

  it 'disables probe when max_processing_time is zero' do
    # Instrument the method
    instrumenter.hook_method(probe, responder)

    # Execute the instrumented method
    result = HookTestClass.new.hook_test_method

    # Verify method still works correctly
    expect(result).to eq 42

    # Verify probe was executed once
    expect(observed_calls.length).to eq 1

    # Verify circuit breaker triggered and probe was disabled
    expect(disabled_calls.length).to eq 1
    expect(disabled_calls.first[:probe]).to eq probe
    expect(disabled_calls.first[:duration]).to be >= 0
    expect(probe.enabled?).to be false

    # Verify subsequent calls do not execute the probe
    HookTestClass.new.hook_test_method
    expect(observed_calls.length).to eq 1  # Still 1, not 2
    expect(disabled_calls.length).to eq 1  # Still 1, not 2
  end
end
