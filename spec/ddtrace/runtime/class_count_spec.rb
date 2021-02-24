require 'spec_helper'
require 'ddtrace/runtime/class_count'

RSpec.describe Datadog::Runtime::ClassCount do
  describe '::available?' do
    subject(:available?) { described_class.available? }

    it { is_expected.to be !(PlatformHelpers.jruby? || PlatformHelpers.truffleruby?) }
  end

  describe '::value' do
    before { skip 'Not supported on current platform' if (PlatformHelpers.jruby? || PlatformHelpers.truffleruby?) }

    subject(:value) { described_class.value }

    it { is_expected.to be_a_kind_of(Integer) }
  end
end
