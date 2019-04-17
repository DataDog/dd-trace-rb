# encoding: utf-8

require 'spec_helper'
require 'ddtrace/runtime/gc'

RSpec.describe Datadog::Runtime::GC do
  describe '::stat' do
    subject(:stat) { described_class.stat }
    it { is_expected.to be_a_kind_of(Hash) }
  end

  describe '::available?' do
    subject(:available?) { described_class.available? }
    it { is_expected.to be true }
  end
end
