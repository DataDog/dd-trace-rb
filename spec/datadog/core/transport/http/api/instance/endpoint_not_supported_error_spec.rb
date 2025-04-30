require 'spec_helper'

require 'datadog/core/transport/http/api/instance'

RSpec.describe Datadog::Core::Transport::HTTP::API::Instance::EndpointNotSupportedError do
  describe '#message' do
    let(:spec) { double(Datadog::Core::Transport::HTTP::API::Instance) }

    let(:error) do
      described_class.new('input', spec)
    end

    it 'produces the expected message' do
      expect(error.message).to eq('input not supported for this API!')
    end
  end
end
