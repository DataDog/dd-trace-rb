# frozen_string_literal: true

require 'spec_helper'
require 'opentelemetry/sdk'
require 'datadog/opentelemetry'

RSpec.describe Datadog::OpenTelemetry::SDK::IdGenerator do
  describe '.generate_trace_id' do
    subject(:id) { described_class.generate_trace_id }

    it 'returns a 16-byte string' do
      expect(id.bytesize).to eq(16)
    end

    it 'is not the OpenTelemetry INVALID_TRACE_ID' do
      expect(id).not_to eq(::OpenTelemetry::Trace::INVALID_TRACE_ID)
    end

    it 'generates different IDs on successive calls' do
      ids = Array.new(10) { described_class.generate_trace_id }
      expect(ids.uniq.size).to eq(10)
    end

    context 'when DD_TRACE_128_BIT_TRACEID_GENERATION_ENABLED is true (default)' do
      before do
        allow(Datadog.configuration.tracing).to receive(:trace_id_128_bit_generation_enabled).and_return(true)
      end

      it 'produces the Datadog 128-bit trace ID format [32-bit timestamp | 32 zeros | 64-bit random]' do
        allow(Datadog::Core::Utils::Time).to receive(:now).and_return(0xffffffff)
        allow(Datadog::Tracing::Utils).to receive(:next_id).and_return(0xaaaaaaaaaaaaaaaa)

        expect(id).to eq([0xffffffff00000000, 0xaaaaaaaaaaaaaaaa].pack('Q>Q>'))
      end

      it 'encodes a 32-bit timestamp in the upper 4 bytes' do
        now = Time.now.to_i
        timestamp = id.byteslice(0, 4).unpack1('N')
        expect(timestamp).to be_between(now - 2, now + 2)
      end

      it 'has 4 zero bytes after the timestamp' do
        expect(id.byteslice(4, 4)).to eq("\x00".b * 4)
      end

      it 'has random lower 8 bytes' do
        expect(id.byteslice(8, 8)).not_to eq("\x00".b * 8)
      end
    end

    context 'when DD_TRACE_128_BIT_TRACEID_GENERATION_ENABLED is false' do
      before do
        allow(Datadog.configuration.tracing).to receive(:trace_id_128_bit_generation_enabled).and_return(false)
      end

      it 'zero-pads a 64-bit trace ID to 16 bytes' do
        allow(Datadog::Tracing::Utils).to receive(:next_id).and_return(0xaaaaaaaaaaaaaaaa)

        expect(id).to eq([0x0000000000000000, 0xaaaaaaaaaaaaaaaa].pack('Q>Q>'))
      end

      it 'zero-pads the upper 8 bytes' do
        expect(id.byteslice(0, 8)).to eq("\x00".b * 8)
      end

      it 'has non-zero lower 8 bytes' do
        expect(id.byteslice(8, 8)).not_to eq("\x00".b * 8)
      end
    end
  end
end
