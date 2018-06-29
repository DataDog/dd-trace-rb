require 'spec_helper'
require 'ddtrace'
require 'restclient/request'

RSpec.describe Datadog::Contrib::RestClient::Patcher do
  describe '.patch' do
    let(:rest_client_request_class) { class_double('RestClient::Request').as_stubbed_const }

    before do
      class_double('RestClient::Request').as_stubbed_const

      rest_client_request_class.class_eval do
        alias_method :execute, :to_s unless respond_to?(:execute)
      end

      described_class.send(:unpatch)
    end

    context 'when delayed job is not present' do
      before do
        hide_const('RestClient::Request')
      end

      it 'does not patch the code' do
        expect { described_class.patch }.not_to(change { described_class.patched? })
      end
    end

    it 'patches the code' do
      expect { described_class.patch }.to change { described_class.patched? }.from(false).to(true)
    end

    it 'adds RequestPatch to ancestors of Request class' do
      expect { described_class.patch }
        .to change { rest_client_request_class.ancestors }.to include(Datadog::Contrib::RestClient::RequestPatch)
    end
  end
end
