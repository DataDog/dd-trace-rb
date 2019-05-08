require 'spec_helper'

require 'ddtrace'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/distributed_headers/headers'

RSpec.describe Datadog::DistributedHeaders::Headers do
  subject(:headers) do
    described_class.new(env)
  end
  let(:env) { {} }

  # Helper to format env header keys
  def env_header(name)
    "http-#{name}".upcase!.tr('-', '_')
  end

  describe '#header' do
    context 'header' do
      context 'not present' do
        it { expect(headers.header('request_id')).to be_nil }
      end

      context 'is nil' do
        let(:env) { { env_header('request_id') => nil } }
        it { expect(headers.header('request_id')).to be_nil }
      end

      context 'is empty string' do
        let(:env) { { env_header('request_id') => '' } }
        it { expect(headers.header('request_id')).to be_nil }
      end

      context 'is set' do
        %w{
        request_id
        request-id
        REQUEST_ID
        REQUEST-ID
        Request-ID
        }.each do |header|
          context "fetched as #{header}" do
            let(:env) { { env_header('request_id') => 'rid' } }
            it { expect(headers.header(header)).to eq('rid') }
          end
        end
      end
    end
  end
end
