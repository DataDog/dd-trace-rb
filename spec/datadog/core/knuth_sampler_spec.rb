require 'spec_helper'
require 'datadog/core/knuth_sampler'

RSpec.describe Datadog::Core::KnuthSampler do
  before { allow(Datadog).to receive(:logger).and_return(logger) }

  let(:logger) { instance_double(Datadog::Core::Logger) }

  describe '#initialize' do
    context 'when no arguments provided' do
      subject(:sampler) { described_class.new }

      it { expect(sampler.sample?(0)).to be(true) }
      it { expect(sampler.sample?(1)).to be(true) }
    end

    context 'when rate is negative' do
      subject(:sampler) { described_class.new(-1.0) }

      it 'logs warning and falls back to 1.0' do
        expect(logger).to receive(:warn).with('Sample rate is not between 0.0 and 1.0, falling back to 1.0')
        expect(sampler.sample?(0)).to be(true)
      end
    end

    context 'when rate is greater than 1.0' do
      subject(:sampler) { described_class.new(1.5) }

      it 'logs warning and falls back to 1.0' do
        expect(logger).to receive(:warn).with('Sample rate is not between 0.0 and 1.0, falling back to 1.0')
        expect(sampler.sample?(0)).to be(true)
      end
    end

    context 'when rate is ~0.0' do
      subject(:sampler) { described_class.new(Float::MIN) }

      it { expect(sampler.sample?(1)).to be(false) }
      it { expect(sampler.sample?(12345)).to be(false) }
    end

    context 'when rate is 1.0' do
      subject(:sampler) { described_class.new(1.0) }

      it { expect(sampler.sample?(0)).to be(true) }
      it { expect(sampler.sample?(1)).to be(true) }
    end

    context 'when custom knuth_factor is provided' do
      it 'uses the custom factor for sampling' do
        result_default = described_class.new(0.5).sample?(1)
        result_custom = described_class.new(0.5, knuth_factor: 1111111111111111111).sample?(1)

        expect(result_default).not_to eq(result_custom)
      end
    end
  end

  describe '#rate=' do
    subject(:sampler) { described_class.new(1.0) }

    context 'when rate is valid' do
      it { expect { sampler.rate = Float::MIN }.to change { sampler.sample?(12345) }.from(true).to(false) }
    end

    context 'when rate is negative' do
      it 'logs warning and falls back to 1.0' do
        expect(logger).to receive(:warn).with('Sample rate is not between 0.0 and 1.0, falling back to 1.0')
        sampler.rate = -0.5
        expect(sampler.sample?(12345)).to be(true)
      end
    end

    context 'when rate is greater than 1.0' do
      it 'logs warning and falls back to 1.0' do
        expect(logger).to receive(:warn).with('Sample rate is not between 0.0 and 1.0, falling back to 1.0')
        sampler.rate = 2.0
        expect(sampler.sample?(12345)).to be(true)
      end
    end
  end

  describe '#sample?' do
    context 'when rate is 1.0' do
      subject(:sampler) { described_class.new(1.0) }

      it { expect(sampler.sample?(12345)).to be(true) }
    end

    context 'when rate is ~0.0' do
      subject(:sampler) { described_class.new(Float::MIN) }

      it { expect(sampler.sample?(12345)).to be(false) }
    end

    context 'when rate is 0.5' do
      subject(:sampler) { described_class.new(0.5) }

      it 'is deterministic' do
        expect(sampler.sample?(12345)).to eq(sampler.sample?(12345))
      end

      it 'samples approximately 50% of sequential inputs' do
        sampled_count = (0...1000).count { |i| sampler.sample?(i) }
        expect(sampled_count).to be_within(100).of(500)
      end
    end

    context 'with specific inputs and 0.5 rate' do
      subject(:sampler) { described_class.new(0.5) }

      {
        12078589664685934330 => false,
        13794769880582338323 => true,
        1882305164521835798 => false,
        5198373796167680436 => true,
        6272545487220484606 => true,
        8696342848850656916 => true,
        18444899399302180860 => true,
        18444899399302180862 => true,
        9223372036854775808 => true
      }.each do |input, expected|
        it { expect(sampler.sample?(input)).to be(expected) }
      end
    end

    context 'when rate is 0.1' do
      subject(:sampler) { described_class.new(0.1) }

      it 'samples ~10% of 1000 inputs' do
        sampled_count = (0...1000).count { |i| sampler.sample?(i) }
        expect(sampled_count).to be_within(15).of(100)
      end
    end

    context 'when rate is 0.25' do
      subject(:sampler) { described_class.new(0.25) }

      it 'samples ~25% of 1000 inputs' do
        sampled_count = (0...1000).count { |i| sampler.sample?(i) }
        expect(sampled_count).to be_within(38).of(250)
      end
    end

    context 'when rate is 0.9' do
      subject(:sampler) { described_class.new(0.9) }

      it 'samples ~90% of 1000 inputs' do
        sampled_count = (0...1000).count { |i| sampler.sample?(i) }
        expect(sampled_count).to be_within(135).of(900)
      end
    end
  end
end
