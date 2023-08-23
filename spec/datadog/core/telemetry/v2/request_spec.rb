# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/telemetry/v2/request'

RSpec.describe Datadog::Core::Telemetry::V2::Request do
  subject(:request) { described_class.new(request_type) }

  let(:request_type) { 'test-type' }

  describe '#to_h' do
    subject(:to_h) { request.to_h }

    it 'includes request_type' do
      is_expected.to eq({ request_type: 'test-type' })
    end
  end
end
