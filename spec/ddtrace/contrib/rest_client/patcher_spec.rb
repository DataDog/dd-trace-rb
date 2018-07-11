require 'spec_helper'
require 'ddtrace'
require 'restclient/request'

RSpec.describe Datadog::Contrib::RestClient::Patcher do
  describe '.patch' do
    let(:rest_client_request_class) { class_double('RestClient::Request').as_stubbed_const }

    before do
      described_class.undo(:rest_client)
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
