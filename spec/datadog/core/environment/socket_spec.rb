require 'spec_helper'
require 'datadog/core/environment/socket'

RSpec.describe Datadog::Core::Environment::Socket do
  describe '::hostname' do
    subject(:hostname) { described_class.hostname }

    it { is_expected.to be_a_kind_of(String) }
  end
end
