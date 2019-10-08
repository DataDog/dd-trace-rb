require 'spec_helper'
require 'ddtrace'
require 'httparty'
require 'httparty/request'

RSpec.describe Datadog::Contrib::HTTParty::Patcher do
  describe '.patch' do
    it 'adds RequestPatch to ancestors of Request class' do
      described_class.patch

      expect(HTTParty::Request.ancestors).to include(Datadog::Contrib::HTTParty::RequestPatch)
    end

    it 'adds ModulePatch to ancestors of HTTParty::ClassMethods' do
      described_class.patch

      expect(HTTParty::ClassMethods.ancestors).to include(Datadog::Contrib::HTTParty::ModulePatch)
    end
  end
end
