require 'datadog/tracing/contrib/propagation/sql_comment/mode'

RSpec.describe Datadog::Tracing::Contrib::Propagation::SqlComment::Mode do
  let(:append) { false }
  let(:inject_sql_basehash) { false }

  describe '#enabled?' do
    [
      ['disabled', false],
      ['service', true],
      ['full', true],
      ['undefined', false]
    ].each do |string, result|
      context "when given `#{string}`" do
        subject { described_class.new(string, append, inject_sql_basehash).enabled? }
        it { is_expected.to be result }
      end
    end
  end

  describe '#service?' do
    [
      ['disabled', false],
      ['service', true],
      ['full', false],
      ['undefined', false]
    ].each do |string, result|
      context "when given `#{string}`" do
        subject { described_class.new(string, append, inject_sql_basehash).service? }
        it { is_expected.to be result }
      end
    end
  end

  describe '#full?' do
    [
      ['disabled', false],
      ['service', false],
      ['full', true],
      ['undefined', false]
    ].each do |string, result|
      context "when given `#{string}`" do
        subject { described_class.new(string, append, inject_sql_basehash).full? }
        it { is_expected.to be result }
      end
    end
  end

  describe '#append?' do
    [
      [false, false],
      [true, true]
    ].each do |value, result|
      context "when given `#{value}`" do
        subject { described_class.new('full', value, inject_sql_basehash).append? }
        it { is_expected.to be result }
      end
    end
  end

  describe '#inject_sql_basehash?' do
    [
      [false, false],
      [true, true]
    ].each do |value, result|
      context "when given `#{value}`" do
        subject { described_class.new('service', false, value).inject_sql_basehash? }
        it { is_expected.to be result }
      end
    end
  end
end
