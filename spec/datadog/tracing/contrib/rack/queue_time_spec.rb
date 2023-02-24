require 'datadog/tracing/contrib/support/spec_helper'

require 'rack'
require 'ddtrace'
require 'datadog/tracing/contrib/rack/request_queue'

RSpec.describe Datadog::Tracing::Contrib::Rack::QueueTime do
  describe '#get_request_start' do
    subject(:request_start) { described_class.get_request_start(env) }

    context 'given a Rack env with' do
      context 'milliseconds' do
        context described_class::REQUEST_START do
          let(:env) { { described_class::REQUEST_START => "t=#{value}" } }
          let(:value) { 1512379167.574 }

          it { expect(request_start.to_f).to eq(value) }

          context 'but does not start with t=' do
            let(:env) { { described_class::REQUEST_START => value } }

            it { expect(request_start.to_f).to eq(value) }
          end

          context 'without decimal places' do
            let(:env) { { described_class::REQUEST_START => value } }
            let(:value) { 1512379167574 }

            it { expect(request_start.to_f).to eq(1512379167.574) }
          end

          context 'but a malformed value' do
            let(:value) { 'foobar' }

            it { is_expected.to be nil }
          end

          context 'before the start of the acceptable time range' do
            let(:value) { 999_999_999.000 }

            it { is_expected.to be nil }
          end
        end

        context described_class::QUEUE_START do
          let(:env) { { described_class::QUEUE_START => "t=#{value}" } }
          let(:value) { 1512379167.574 }

          it { expect(request_start.to_f).to eq(value) }
        end
      end

      context 'microseconds' do
        context described_class::REQUEST_START do
          let(:env) { { described_class::REQUEST_START => "t=#{value}" } }
          let(:value) { 1570633834.463123 }

          it { expect(request_start.to_f).to eq(value) }

          context 'but does not start with t=' do
            let(:env) { { described_class::REQUEST_START => value } }

            it { expect(request_start.to_f).to eq(value) }
          end

          context 'without decimal places' do
            let(:env) { { described_class::REQUEST_START => value } }
            let(:value) { 1570633834463123 }

            it { expect(request_start.to_f).to eq(1570633834.463123) }
          end

          context 'but a malformed value' do
            let(:value) { 'foobar' }

            it { is_expected.to be nil }
          end
        end

        context described_class::QUEUE_START do
          let(:env) { { described_class::QUEUE_START => "t=#{value}" } }
          let(:value) { 1570633834.463123 }

          it { expect(request_start.to_f).to eq(value) }
        end
      end

      context 'nothing' do
        let(:env) { {} }

        it { is_expected.to be nil }
      end
    end
  end
end
