require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'
require 'restclient/request'

RSpec.describe Datadog::Contrib::RestClient::Patcher do
  describe '.patch' do
    it 'adds RequestPatch to ancestors of Request class' do
      described_class.patch

      expect(RestClient::Request.ancestors).to include(Datadog::Contrib::RestClient::RequestPatch)
    end
  end
end
