require 'spec_helper'

require 'datadog/core/transport/http/api/spec'

RSpec.describe Datadog::Core::Transport::HTTP::API::Spec::EndpointNotDefinedError do
  describe '#message' do
    let(:spec) { Datadog::Core::Transport::HTTP::API::Spec.new }

    let(:error) do
      described_class.new('input', spec)
    end

    it 'produces the expected message' do
      expect(error.message).to eq('No input endpoint is defined for API specification!')
    end
  end
end
