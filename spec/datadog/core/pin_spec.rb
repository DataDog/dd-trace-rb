require 'spec_helper'

require 'datadog/core/pin'

RSpec.describe Datadog::Core::Pin do
  subject(:pin) { described_class.new(**options) }
  let(:options) { {} }
  let(:target) { Object.new }

  describe '.get_from' do
    subject(:returned_pin) { described_class.get_from(target) }

    context 'called against' do
      context '0' do
        let(:target) { 0 }

        it { is_expected.to be nil }
      end

      context 'nil' do
        let(:target) { nil }

        it { is_expected.to be nil }
      end

      context 'self' do
        let(:target) { self }

        it { is_expected.to be nil }
      end
    end

    context 'when a custom pin has already been defined' do
      let(:target_class) do
        Class.new do
          def datadog_pin
            @custom_attribute
          end

          def datadog_pin=(_pin)
            @custom_attribute = 'The PIN is set!'
          end
        end
      end

      let(:target) { target_class.new }

      before { pin.onto(target) }

      it 'returns the custom pin' do
        is_expected.to eq('The PIN is set!')
      end
    end
  end

  describe '.set_on' do
    subject(:set_on) { described_class.set_on(target, **options) }
    let(:options) { { a_setting: :a_value } }

    context 'given an object without a Pin' do
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(set_on[:a_setting]).to be(:a_value) }
    end

    context 'given an object with a Pin' do
      context 'and a setting that does not conflict' do
        let(:original_options) { { original_setting: :original_value } }

        before { described_class.set_on(target, **original_options) }

        it { is_expected.to be_a_kind_of(described_class) }
        it { expect(set_on[:original_setting]).to be(:original_value) }
        it { expect(set_on[:a_setting]).to be(:a_value) }
      end

      context 'and a setting that conflicts' do
        let(:original_options) { { a_setting: :original_value } }

        before { described_class.set_on(target, **original_options) }

        it { is_expected.to be_a_kind_of(described_class) }
        it { expect(set_on[:a_setting]).to be(:a_value) }
      end

      context 'which has a custom pin has already defined' do
        let(:target_class) do
          Class.new do
            def datadog_pin
              @custom_attribute
            end

            def datadog_pin=(_pin)
              @custom_attribute = { custom_pin: true }
            end
          end
        end

        let(:target) { target_class.new }

        before { pin.onto(target) }

        it 'returns the custom pin' do
          is_expected.to eq({ custom_pin: true }.merge(options))
        end
      end
    end
  end

  describe '#initialize' do
    before { pin }

    context 'when given some options' do
      let(:options) do
        {
          app: double('app'),
          app_type: double('app_type'),
          tags: double('tags')
        }
      end

      it do
        expect(pin[:app]).to eq(options[:app])
        expect(pin[:app_type]).to eq(options[:app_type])
        expect(pin[:tags]).to eq(options[:tags])
      end
    end
  end

  describe '#[]' do
    subject(:get) { pin[key] }
    let(:key) { :a_setting }

    context 'when setting is not set' do
      it { is_expected.to be nil }
    end

    context 'when setting is set' do
      let(:value) { :a_value }

      before { pin[key] = value }

      it { is_expected.to be value }
    end
  end

  describe '#[]=' do
    subject(:set) { pin[key] = value }
    let(:key) { :a_setting }
    let(:value) { :a_value }

    context 'when setting is not set' do
      it do
        set
        expect(pin[key]).to be value
      end
    end

    context 'when setting is set' do
      before { pin[key] = :old_value }

      it do
        set
        expect(pin[key]).to be value
      end
    end
  end

  describe '#key?' do
    subject(:key?) { pin.key?(key) }
    let(:key) { :a_setting }

    context 'when setting is not set' do
      it { is_expected.to be false }
    end

    context 'when setting is set' do
      before { pin[key] = :a_value }

      it { is_expected.to be true }
    end
  end

  describe '#onto' do
    subject(:onto) { pin.onto(target) }
    let(:returned_pin) { described_class.get_from(target) }

    before { onto }

    it 'attaches the pin to the target' do
      expect(returned_pin).to be(pin)
    end
  end

  describe '#to_s' do
    subject(:string) { pin.to_s }

    let(:options) { { app: 'anapp', app_type: 'db' } }

    it { is_expected.to eq('Pin(app:anapp, app_type:db)') }
  end

  describe '#datadog_pin' do
    let(:returned_pin) { target.datadog_pin }

    before { pin.onto(target) }

    it { expect(returned_pin).to be(pin) }
  end
end
