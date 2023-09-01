require 'spec_helper'

require 'datadog/tracing/transport/http/api/spec'

RSpec.describe Datadog::Tracing::Transport::HTTP::API::Spec do
  subject(:spec) { described_class.new }

  describe '#initialize' do
    it 'yields to the block with the HTTP::Env' do
      expect { |b| described_class.new(&b) }.to yield_with_args(kind_of(described_class))
    end
  end
end
