require 'spec_helper'

require 'securerandom'
require 'ddtrace'

RSpec.describe Datadog::Configuration::FallbackPin do
  subject(:fallback_pin) { described_class.new(*pins) }

  let(:pins) { [pin_one, pin_two] }
  let(:pin_one) { Datadog::Pin.new(nil) }
  let(:pin_two) { Datadog::Pin.new(nil) }

  Datadog::Configuration::FallbackPin::OPTIONS.each do |option|
    describe "\##{option}" do
      subject(:result) { fallback_pin.send(option) }

      context 'when the first pin has a value' do
        let(:value) { SecureRandom.uuid }
        before(:each) { pin_one.send("#{option}=", value) }
        it { is_expected.to eq(value) }
      end

      context 'when the only second pin has a value' do
        let(:value) { SecureRandom.uuid }
        before(:each) do
          pin_one.send("#{option}=", nil)
          pin_two.send("#{option}=", value)
        end
        it { is_expected.to eq(value) }
      end

      context 'when neither pin has a value' do
        before(:each) do
          pin_one.send("#{option}=", nil)
          pin_two.send("#{option}=", nil)
        end
        it { is_expected.to be nil }
      end
    end

    describe "\##{option}=" do
      subject(:result) { fallback_pin.send("#{option}=", value) }
      let(:value) { SecureRandom.uuid }

      it do
        is_expected.to eq(value)
        expect(fallback_pin.send(option)).to eq(value)
      end
    end
  end
end
