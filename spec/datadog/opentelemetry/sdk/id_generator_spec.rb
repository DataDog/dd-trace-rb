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

    it 'has zeroed upper 8 bytes for Datadog 64-bit trace ID compatibility' do
      expect(id.byteslice(0, 8)).to eq("\x00".b * 8)
    end

    it 'has non-zero lower 8 bytes' do
      expect(id.byteslice(8, 8)).not_to eq("\x00".b * 8)
    end

    it 'is not the OpenTelemetry INVALID_TRACE_ID' do
      expect(id).not_to eq(::OpenTelemetry::Trace::INVALID_TRACE_ID)
    end

    it 'generates different IDs on successive calls' do
      ids = Array.new(10) { described_class.generate_trace_id }
      expect(ids.uniq.size).to eq(10)
    end
  end
end
