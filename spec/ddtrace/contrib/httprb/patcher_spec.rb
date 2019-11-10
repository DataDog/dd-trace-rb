require 'spec_helper'
require 'ddtrace'
require 'http'

RSpec.describe Datadog::Contrib::Httprb::Patcher do
  describe '.patch' do
    it 'adds DatadogWrap to Features of HTTP class' do
      described_class.patch

      expect(HTTP::Options.available_features).to include(:datadog_wrap)      
    end
  end
end
