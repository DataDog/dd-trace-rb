# encoding: utf-8

require 'spec_helper'
require 'ddtrace/runtime/class_count'

RSpec.describe Datadog::Runtime::ClassCount do
  describe '::value' do
    subject(:value) { described_class.value }
    it { is_expected.to be_a_kind_of(Integer) }
  end

  describe '::available?' do
    subject(:available?) { described_class.available? }
    it { is_expected.to be true }
  end
end
