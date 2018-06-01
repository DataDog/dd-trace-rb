require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configuration::Proxy do
  subject(:proxy) { described_class.new(configurable_module) }

  let(:configurable_module) do
    Module.new do
      include Datadog::Configurable
      option :x, default: :a
      option :y, default: :b
    end
  end

  describe '#[]' do
    before(:each) do
      proxy[:x] = 1
      proxy[:y] = 2
    end

    it do
      expect(proxy[:x]).to eq(1)
      expect(proxy[:y]).to eq(2)
    end
  end

  describe '#to_h' do
    subject(:hash) { proxy.to_h }
    it { is_expected.to eq(x: :a, y: :b) }
  end

  describe '#to_hash' do
    subject(:hash) { proxy.to_hash }
    it { is_expected.to eq(x: :a, y: :b) }
  end

  describe '#merge' do
    subject(:result) { proxy.merge(hash) }
    let(:hash) { { z: :c } }
    it { is_expected.to eq(x: :a, y: :b, z: :c) }
  end
end
