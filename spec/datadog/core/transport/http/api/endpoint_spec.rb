require 'spec_helper'

require 'datadog/core/transport/http/env'
require 'datadog/core/transport/http/api/endpoint'

RSpec.describe Datadog::Core::Transport::HTTP::API::Endpoint do
  subject(:endpoint) { described_class.new(verb, path) }

  let(:verb) { double('verb') }
  let(:path) { double('path') }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        verb: verb,
        path: path
      )
    end
  end

  describe '#call' do
    let(:env) { instance_double(Datadog::Core::Transport::HTTP::Env) }

    before do
      expect(env).to receive(:verb=).with(verb)
      expect(env).to receive(:path=).with(path)
    end

    it 'yields to the block with the HTTP::Env' do
      expect { |b| endpoint.call(env, &b) }.to yield_with_args(env)
    end
  end
end
