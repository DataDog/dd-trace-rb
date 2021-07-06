require 'spec_helper'
require 'datadog/core/environment/class_count'

RSpec.describe Datadog::Core::Environment::ClassCount do
  describe '::available?' do
    subject(:available?) { described_class.available? }

    it { is_expected.to be !(PlatformHelpers.jruby? || PlatformHelpers.truffleruby?) }
  end

  describe '::value' do
    before { skip 'Not supported on current platform' unless described_class.available? }

    subject(:value) { described_class.value }

    it { is_expected.to be_a_kind_of(Integer) }
  end
end
