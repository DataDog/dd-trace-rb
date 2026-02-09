# frozen_string_literal: true

require 'datadog/di/spec_helper'
require 'datadog/di/instrumenter'
require_relative 'hook_method'
require_relative 'hook_line_basic'

RSpec.describe 'Datadog::DI::Instrumenter circuit breaker' do
  di_test

  let(:observed_calls) { [] }
  let(:disabled_calls) { [] }

  # Helper method to generate a deeply nested hash
  # Creates a hash with the specified number of keys at each level
  # and nests to the specified depth
  def generate_deep_hash(keys_per_level, depth)
    return "leaf_value" if depth == 0

    hash = {}
    keys_per_level.times do |i|
      hash[:"key_#{i}"] = generate_deep_hash(keys_per_level, depth - 1)
    end
    hash
  end

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
    allow(settings.dynamic_instrumentation.internal).to receive(:untargeted_trace_points).and_return(false)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_depth).and_return(10)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_attribute_count).and_return(20)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_collection_size).and_return(20)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_string_length).and_return(100)
    allow(settings.dynamic_instrumentation).to receive(:redacted_type_names).and_return([])
    allow(settings.dynamic_instrumentation).to receive(:redacted_identifiers).and_return([])
    allow(settings.dynamic_instrumentation).to receive(:redaction_excluded_identifiers).and_return([])
    allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(true)
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
        @disabled_calls << {probe: probe, duration: duration}
      end
    end.new(observed_calls, disabled_calls)
  end

  context 'method probe' do
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

    context 'when max_processing_time is zero' do
      before do
        allow(settings.dynamic_instrumentation.internal).to receive(:max_processing_time).and_return(0)
      end

      it 'disables probe after first execution' do
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

    context 'when max_processing_time is high' do
      before do
        allow(settings.dynamic_instrumentation.internal).to receive(:max_processing_time).and_return(1000)
      end

      it 'keeps probe enabled after multiple executions' do
        # Instrument the method
        instrumenter.hook_method(probe, responder)

        # Execute the instrumented method 5 times
        5.times do
          result = HookTestClass.new.hook_test_method
          expect(result).to eq 42
        end

        # Verify probe was executed 5 times
        expect(observed_calls.length).to eq 5

        # Verify circuit breaker never triggered
        expect(disabled_calls).to be_empty
        expect(probe.enabled?).to be true
      end
    end

    context 'when max_processing_time is very small with snapshot capture' do
      let(:snapshot_probe) do
        Datadog::DI::Probe.new(
          id: 'test-probe-snapshot',
          type: :log,
          type_name: 'HookTestClass',
          method_name: 'hook_test_method_with_arg',
          capture_snapshot: true,
        )
      end

      before do
        allow(settings.dynamic_instrumentation.internal).to receive(:max_processing_time).and_return(1e-8)
      end

      after do
        instrumenter.unhook(snapshot_probe)
      end

      it 'disables probe after first execution due to snapshot overhead' do
        # Generate a deeply nested hash (10 keys per level, 5 levels deep)
        deep_hash = generate_deep_hash(10, 5)

        # Instrument the method
        instrumenter.hook_method(snapshot_probe, responder)

        # Execute the instrumented method with the deep hash
        result = HookTestClass.new.hook_test_method_with_arg(deep_hash)

        # Verify method still works correctly
        expect(result).to eq deep_hash

        # Verify probe was executed once
        expect(observed_calls.length).to eq 1

        # Verify snapshot captured the argument with 10 top-level keys
        context = observed_calls.first
        expect(context).to be_a(Datadog::DI::Context)
        expect(context.serialized_entry_args).to be_a(Hash)
        expect(context.serialized_entry_args).to have_key(:arg1)

        arg_data = context.serialized_entry_args[:arg1]
        expect(arg_data).to be_a(Hash)
        expect(arg_data[:type]).to eq('Hash')
        expect(arg_data[:entries]).to be_a(Array)

        # Verify all 10 top-level keys are captured
        expect(arg_data[:entries].size).to eq(10)
        expect(arg_data[:entries][0][0]).to eq({type: 'Symbol', value: 'key_0'})
        expect(arg_data[:entries][9][0]).to eq({type: 'Symbol', value: 'key_9'})

        # Verify circuit breaker triggered and probe was disabled
        expect(disabled_calls.length).to eq 1
        expect(disabled_calls.first[:probe]).to eq snapshot_probe
        expect(disabled_calls.first[:duration]).to be >= 0
        expect(snapshot_probe.enabled?).to be false
      end
    end
  end

  context 'line probe' do
    let(:line_probe) do
      Datadog::DI::Probe.new(
        id: 'test-line-probe-1',
        type: :log,
        file: 'hook_line_basic.rb',
        line_no: 3,
      )
    end

    before do
      # We need untargeted trace points since the file is already loaded
      allow(settings.dynamic_instrumentation.internal).to receive(:untargeted_trace_points).and_return(true)
    end

    after do
      instrumenter.unhook(line_probe)
    end

    context 'when max_processing_time is zero' do
      before do
        allow(settings.dynamic_instrumentation.internal).to receive(:max_processing_time).and_return(0)
      end

      it 'disables probe after first execution' do
        # Instrument the line
        instrumenter.hook_line(line_probe, responder)

        # Execute the instrumented method
        result = HookLineBasicTestClass.new.test_method

        # Verify method still works correctly
        expect(result).to eq 42

        # Verify probe was executed once
        expect(observed_calls.length).to eq 1

        # Verify circuit breaker triggered and probe was disabled
        expect(disabled_calls.length).to eq 1
        expect(disabled_calls.first[:probe]).to eq line_probe
        expect(disabled_calls.first[:duration]).to be >= 0
        expect(line_probe.enabled?).to be false

        # Verify subsequent calls do not execute the probe
        HookLineBasicTestClass.new.test_method
        expect(observed_calls.length).to eq 1  # Still 1, not 2
        expect(disabled_calls.length).to eq 1  # Still 1, not 2
      end
    end

    context 'when max_processing_time is high' do
      before do
        allow(settings.dynamic_instrumentation.internal).to receive(:max_processing_time).and_return(1000)
      end

      it 'keeps probe enabled after multiple executions' do
        # Instrument the line
        instrumenter.hook_line(line_probe, responder)

        # Execute the instrumented method 5 times
        5.times do
          result = HookLineBasicTestClass.new.test_method
          expect(result).to eq 42
        end

        # Verify probe was executed 5 times
        expect(observed_calls.length).to eq 5

        # Verify circuit breaker never triggered
        expect(disabled_calls).to be_empty
        expect(line_probe.enabled?).to be true
      end
    end

    context 'when max_processing_time is very small with snapshot capture' do
      let(:snapshot_line_probe) do
        Datadog::DI::Probe.new(
          id: 'test-line-probe-snapshot',
          type: :log,
          file: 'hook_line_basic.rb',
          line_no: 7,
          capture_snapshot: true,
        )
      end

      before do
        allow(settings.dynamic_instrumentation.internal).to receive(:max_processing_time).and_return(1e-8)
      end

      after do
        instrumenter.unhook(snapshot_line_probe)
      end

      it 'disables probe after first execution due to snapshot overhead' do
        # Generate a deeply nested hash (10 keys per level, 5 levels deep)
        deep_hash = generate_deep_hash(10, 5)

        # Instrument the line
        instrumenter.hook_line(snapshot_line_probe, responder)

        # Execute the instrumented method with the deep hash
        result = HookLineBasicTestClass.new.test_method_with_arg(deep_hash)

        # Verify method still works correctly
        expect(result).to eq deep_hash

        # Verify probe was executed once
        expect(observed_calls.length).to eq 1

        # Verify snapshot captured the local variables with all 10 top-level keys
        context = observed_calls.first
        expect(context).to be_a(Datadog::DI::Context)
        expect(context.locals).to be_a(Hash)
        expect(context.locals).to have_key(:arg)

        # Verify all 10 top-level keys are captured without truncation
        arg_hash = context.locals[:arg]
        expect(arg_hash).to be_a(Hash)
        expect(arg_hash.keys.size).to eq(10)
        expect(arg_hash).to have_key(:key_0)
        expect(arg_hash).to have_key(:key_9)

        # Verify circuit breaker triggered and probe was disabled
        expect(disabled_calls.length).to eq 1
        expect(disabled_calls.first[:probe]).to eq snapshot_line_probe
        expect(disabled_calls.first[:duration]).to be >= 0
        expect(snapshot_line_probe.enabled?).to be false
      end
    end
  end
end
