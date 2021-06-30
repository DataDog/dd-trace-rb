require 'spec_helper'
require 'datadog/core/environment/thread_count'

RSpec.describe Datadog::Core::Environment::ThreadCount do
  describe '::value' do
    subject(:value) { described_class.value }

    it { is_expected.to be_a_kind_of(Integer) }
  end

  describe '::available?' do
    subject(:available?) { described_class.available? }

    it { is_expected.to be true }
  end
end
