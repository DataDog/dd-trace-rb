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
      allow(settings).to receive(:propagate_all_exceptions).and_return(false)
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
    it 'returns a hash' do
      expect(builder.build_received(probe)).to be_a(Hash)
    end
  end

  describe '#build_installed' do
    it 'returns a hash' do
      expect(builder.build_installed(probe)).to be_a(Hash)
    end
  end

  describe '#build_emitting' do
    it 'returns a hash' do
      expect(builder.build_emitting(probe)).to be_a(Hash)
    end
  end

  describe '#build_executed' do
    context 'with template' do
      let(:probe) do
        Datadog::DI::Probe.new(id: '123', type: :log, file: 'X', line_no: 1,
          template: 'hello world')
      end

      it 'returns a hash' do
        expect(builder.build_executed(probe)).to be_a(Hash)
      end
    end

    context 'without snapshot capture' do
      let(:probe) do
        Datadog::DI::Probe.new(id: '123', type: :log, file: 'X', line_no: 1,
          capture_snapshot: false)
      end

      it 'returns a hash' do
        expect(builder.build_executed(probe)).to be_a(Hash)
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
          expect(tp).to receive(:binding).and_return(binding)
          expect(tp).to receive(:path).and_return('/foo.rb')
        end
      end

      it 'returns a hash' do
        expect(builder.build_executed(probe, trace_point: trace_point)).to be_a(Hash)
      end
    end
  end
end
