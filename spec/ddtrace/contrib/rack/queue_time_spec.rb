require 'spec_helper'

require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/request_queue'

RSpec.describe Datadog::Contrib::Rack::QueueTime do
  describe '#get_request_start' do
    subject(:request_start) { described_class.get_request_start(env) }

    context 'given a Rack env with' do
      context described_class::REQUEST_START do
        let(:env) { { described_class::REQUEST_START => "t=#{value}" } }
        let(:value) { 1512379167.574 }
        it { expect(request_start.to_f).to eq(value) }

        context 'but a malformed value' do
          let(:value) { 'foobar' }
          it { is_expected.to be nil }
        end
      end

      context described_class::QUEUE_START do
        let(:env) { { described_class::QUEUE_START => "t=#{value}" } }
        let(:value) { 1512379167.574 }
        it { expect(request_start.to_f).to eq(value) }
      end

      context 'nothing' do
        let(:env) { {} }
        it { is_expected.to be nil }
      end
    end
  end
end
