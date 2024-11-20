require "datadog/di/spec_helper"
require 'datadog/di/probe_notification_builder'
require 'datadog/di/serializer'
require 'datadog/di/probe'

# Notification builder is primarily tested via integration tests for
# dynamic instrumentation overall, since the generated payloads depend
# heavily on probe attributes and parameters.
#
# The unit tests here are only meant to catch grave errors in the implementaton,
# not comprehensively verify correctness.

RSpec.describe Datadog::DI::ProbeNotificationBuilder do
  di_test

  let(:settings) do
    double("settings").tap do |settings|
      allow(settings).to receive(:dynamic_instrumentation).and_return(di_settings)
      allow(settings).to receive(:service).and_return('test service')
    end
  end

  let(:di_settings) do
    double("di settings").tap do |settings|
      allow(settings).to receive(:enabled).and_return(true)
      allow(settings).to receive(:redacted_identifiers).and_return([])
      allow(settings).to receive(:redacted_type_names).and_return(%w[])
      allow(settings).to receive(:max_capture_collection_size).and_return(10)
      allow(settings).to receive(:max_capture_attribute_count).and_return(10)
      allow(settings).to receive(:max_capture_depth).and_return(2)
      allow(settings).to receive(:max_capture_string_length).and_return(100)
    end
  end

  let(:redactor) { Datadog::DI::Redactor.new(settings) }
  let(:serializer) { Datadog::DI::Serializer.new(settings, redactor) }

  let(:builder) { described_class.new(settings, serializer) }

  let(:probe) do
    Datadog::DI::Probe.new(id: '123', type: :log, file: 'X', line_no: 1)
  end

  describe '#build_received' do

    let(:payload) do
      builder.build_received(probe)
    end

    let(:expected) do
      {
        ddsource: 'dd_debugger',
        debugger: {
          diagnostics: {
            parentId: nil,
            probeId: '123',
            probeVersion: 0,
            runtimeId: String,
            status: 'RECEIVED',
          },
        },
        message: "Probe 123 has been received correctly",
        service: 'test service',
        timestamp: Integer,
      }
    end

    it 'returns a hash with expected contents' do
      expect(payload).to be_a(Hash)
      expect(payload).to match(expected)
    end
  end

  describe '#build_installed' do

    let(:payload) do
      builder.build_installed(probe)
    end

    let(:expected) do
      {
        ddsource: 'dd_debugger',
        debugger: {
          diagnostics: {
            parentId: nil,
            probeId: '123',
            probeVersion: 0,
            runtimeId: String,
            status: 'INSTALLED',
          },
        },
        message: "Probe 123 has been instrumented correctly",
        service: 'test service',
        timestamp: Integer,
      }
    end

    it 'returns a hash with expected contents' do
      expect(payload).to be_a(Hash)
      expect(payload).to match(expected)
    end
  end

  describe '#build_emitting' do

    let(:payload) do
      builder.build_emitting(probe)
    end

    let(:expected) do
      {
        ddsource: 'dd_debugger',
        debugger: {
          diagnostics: {
            parentId: nil,
            probeId: '123',
            probeVersion: 0,
            runtimeId: String,
            status: 'EMITTING',
          },
        },
        message: "Probe 123 is emitting",
        service: 'test service',
        timestamp: Integer,
      }
    end

    it 'returns a hash with expected contents' do
      expect(payload).to be_a(Hash)
      expect(payload).to match(expected)
    end
  end

  describe '#build_executed' do

    let(:payload) { builder.build_executed(probe) }

    context 'with template' do
      let(:probe) do
        Datadog::DI::Probe.new(id: '123', type: :log, file: 'X', line_no: 1,
          template: 'hello world')
      end

      let(:expected) do
        {
          ddsource: 'dd_debugger',
          'dd.span_id': nil,
          'dd.trace_id': nil,
          'debugger.snapshot': {
            captures: nil,
            evaluationErrors: [],
            id: String,
            language: 'ruby',
            probe: {
              id: '123',
              location: {
                file: nil,
                lines: [1],
              },
              version: 0,
            },
            stack: nil,
            timestamp: Integer,
          },
          message: "hello world",
          service: 'test service',
          timestamp: Integer,
          logger: {
            method: 'no_method',
            name: 'X',
            thread_id: nil,
            thread_name: 'Thread.main',
            version: 2,
          },
          duration: 0,
          host: nil,
        }
      end

      it 'returns a hash with expected contents' do
        expect(payload).to be_a(Hash)
        expect(payload).to match(expected)
      end
    end

    context 'without snapshot capture' do
      let(:probe) do
        Datadog::DI::Probe.new(id: '123', type: :log, file: 'X', line_no: 1,
          capture_snapshot: false)
      end

      let(:expected) do
        {
          ddsource: 'dd_debugger',
          'dd.span_id': nil,
          'dd.trace_id': nil,
          'debugger.snapshot': {
            captures: nil,
            evaluationErrors: [],
            id: String,
            language: 'ruby',
            probe: {
              id: '123',
              location: {
                file: nil,
                lines: [1],
              },
              version: 0,
            },
            stack: nil,
            timestamp: Integer,
          },
          message: nil,
          service: 'test service',
          timestamp: Integer,
          logger: {
            method: 'no_method',
            name: 'X',
            thread_id: nil,
            thread_name: 'Thread.main',
            version: 2,
          },
          duration: 0,
          host: nil,
        }
      end

      it 'returns a hash with expected contents' do
        expect(payload).to be_a(Hash)
        expect(payload).to match(expected)
      end
    end

    context 'with snapshot capture' do
      let(:probe) do
        Datadog::DI::Probe.new(id: '123', type: :log, file: 'X', line_no: 1,
          capture_snapshot: true,)
      end

      let(:trace_point) do
        instance_double(TracePoint).tap do |tp|
          # Returns an empty binding
          expect(tp).to receive(:binding).and_return(get_binding)
          expect(tp).to receive(:path).and_return('/foo.rb')
        end
      end

      let(:get_binding) do
        x = 1
        binding
      end

      let(:payload) do
        builder.build_executed(probe, trace_point: trace_point)
      end

      let(:expected) do
        {
          ddsource: 'dd_debugger',
          'dd.span_id': nil,
          'dd.trace_id': nil,
          'debugger.snapshot': {
            captures: {
              lines: {
                1 => {
                  locals: local_captures,
                },
              },
            },
            evaluationErrors: [],
            id: String,
            language: 'ruby',
            probe: {
              id: '123',
              location: {
                file: '/foo.rb',
                lines: [1],
              },
              version: 0,
            },
            stack: nil,
            timestamp: Integer,
          },
          message: nil,
          service: 'test service',
          timestamp: Integer,
          logger: {
            method: 'no_method',
            name: 'X',
            thread_id: nil,
            thread_name: 'Thread.main',
            version: 2,
          },
          duration: 0,
          host: nil,
        }
      end

      shared_examples 'returns a hash with expected contents' do
        it 'returns a hash with expected contents' do
          expect(payload).to be_a(Hash)
          expect(payload).to match(expected)
        end
      end

      context 'when binding is empty' do
        let(:get_binding) do
          binding
        end

        let(:local_captures) do
          {}
        end

        include_examples 'returns a hash with expected contents'
      end

      context 'when binding is not empty' do
        let(:get_binding) do
          x = 1
          binding
        end

        let(:local_captures) do
          {x: {type: 'Integer', value: '1'}}
        end

        include_examples 'returns a hash with expected contents'
      end
    end
  end
end
