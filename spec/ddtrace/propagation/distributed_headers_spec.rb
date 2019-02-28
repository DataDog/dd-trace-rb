require 'spec_helper'

require 'ddtrace'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/distributed_headers'

RSpec.describe Datadog::DistributedHeaders do
  subject(:headers) do
    described_class.new(env)
  end
  let(:env) { {} }

  # Helper to format env header keys
  def env_header(name)
    "http-#{name}".upcase!.tr('-', '_')
  end

  describe '#origin' do
    context 'no origin header' do
      it { expect(headers.origin).to be_nil }
    end

    context 'incorrect header' do
      [
        'X-DATADOG-ORIGN', # Typo
        'DATADOG-ORIGIN',
        'X-ORIGIN',
        'ORIGIN'
      ].each do |header|
        context header do
          let(:env) { { env_header(header) => 'synthetics' } }

          it { expect(headers.origin).to be_nil }
        end
      end
    end

    context 'origin in header' do
      [
        ['', nil],
        %w[synthetics synthetics],
        %w[origin origin]
      ].each do |value, expected|
        context "set to #{value}" do
          let(:env) { { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => value } }

          it { expect(headers.origin).to eq(expected) }
        end
      end
    end
  end
end
