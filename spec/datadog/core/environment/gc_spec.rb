require 'spec_helper'
require 'datadog/core/environment/gc'

RSpec.describe Datadog::Core::Environment::GC do
  describe '::stat' do
    subject(:stat) { described_class.stat }

    it { is_expected.to be_a_kind_of(Hash) }
  end

  describe '::available?' do
    subject(:available?) { described_class.available? }

    it { is_expected.to be true }
  end
end
