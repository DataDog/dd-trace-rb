require 'datadog/tracing/contrib/propagation/sql_comment/mode'

RSpec.describe Datadog::Tracing::Contrib::Propagation::SqlComment::Mode do
  describe '#enabled?' do
    [
      ['disabled', false],
      ['service', true],
      ['full', true],
      ['undefined', false]
    ].each do |string, result|
      context "when given `#{string}`" do
        subject { described_class.new(string).enabled? }
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
        subject { described_class.new(string).service? }
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
        subject { described_class.new(string).full? }
        it { is_expected.to be result }
      end
    end
  end
end
