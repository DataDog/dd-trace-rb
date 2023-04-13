require 'spec_helper'

require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::Carrier do
  subject(:carrier) { described_class.new }

  describe '#[]' do
    subject(:span) { carrier[key] }

    let(:key) { 'key' }

    it { is_expected.to be nil }
  end

  describe '#[]=' do
    subject(:result) { carrier[key] = value }

    let(:key) { 'key' }
    let(:value) { 'value' }

    it { is_expected.to eq(value) }
  end

  describe '#each' do
    subject(:result) { carrier.each(&block) }

    let(:block) { proc { |key, value| } }

    it { is_expected.to be nil }
  end
end
