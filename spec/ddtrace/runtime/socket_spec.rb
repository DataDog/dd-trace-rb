require 'spec_helper'
require 'ddtrace/runtime/socket'

RSpec.describe Datadog::Runtime::Socket do
  describe '::hostname' do
    subject(:hostname) { described_class.hostname }

    it { is_expected.to be_a_kind_of(String) }
  end
end
