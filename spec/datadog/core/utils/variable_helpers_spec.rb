require 'spec_helper'

require 'datadog/core/utils/variable_helpers'

RSpec.describe Datadog::Core::Utils::VariableHelpers do
  describe '::val_to_bool' do
    subject(:val_to_bool) { described_class.val_to_bool(var) }

    context 'when var is set as' do
      # True values
      [
        'true',
        'TRUE',
        '1',
        ' 1 ',
      ].each do |value|
        context "'#{value}'" do
          let(:var) { value }

          it { is_expected.to be true }
        end
      end

      # False values
      [
        '',
        'false',
        'FALSE',
        '0',
        'arbitrary string',
      ].each do |value|
        context "'#{value}'" do
          let(:var) { value }

          it { is_expected.to be false }
        end
      end
    end
  end

  describe '::val_to_int' do
    let(:default) { double }
    subject(:val_to_int) { described_class.val_to_int(var) }

    context 'when var is set as' do
      context 'nil' do
        let(:var) { nil }

        it { is_expected.to be_nil }
      end

      context 'Integer' do
        let(:var) { 0 }

        it { is_expected.to eq 0 }
      end

      context 'String' do
        let(:var) { '11' }

        it { is_expected.to eq 11 }
      end

      context 'invalid int value' do
        let(:var) { '1.5' }

        it do
          expect do
            is_expected
          end.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe '::val_to_float' do
    let(:default) { double }
    subject(:val_to_float) { described_class.val_to_float(var) }

    context 'when var is set as' do
      context 'nil' do
        let(:var) { nil }

        it { is_expected.to be_nil }
      end

      context 'Integer' do
        let(:var) { 0 }

        it { is_expected.to eq 0.0 }
      end

      context 'String' do
        let(:var) { '11.8' }

        it { is_expected.to eq 11.8 }
      end

      context 'invalid int value' do
        let(:var) { 'hello' }

        it do
          expect do
            is_expected
          end.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe '::val_to_list' do
    let(:default) { double }
    subject(:val_to_list) { described_class.val_to_list(var, default, comma_separated_only: false) }

    context 'and default is defined' do
      let(:var) { nil }
      it { is_expected.to be default }
    end

    context 'when var is set' do
      context '\'\'' do
        let(:var) { '' }

        it { is_expected.to eq([]) }
      end

      context ',' do
        let(:var) { ',' }

        it { is_expected.to eq([]) }
      end

      context '1' do
        let(:var) { '1' }

        it { is_expected.to eq(['1']) }
      end

      context '1,2' do
        let(:var) { '1,2' }

        it { is_expected.to eq(%w[1 2]) }
      end

      context ' 1 , 2 ,  3 ' do
        let(:var) { ' 1 , 2 ,  3 ' }

        it { is_expected.to eq(%w[1 2 3]) }
      end

      context '1 2 3' do
        let(:var) { '1 2 3' }

        it { is_expected.to eq(%w[1 2 3]) }
      end

      context '1,2 3' do
        let(:var) { '1,2 3' }

        it { is_expected.to eq(['1', '2 3']) }
      end

      context ' 1  2   3 ' do
        let(:var) { ' 1  2   3 ' }

        it { is_expected.to eq(%w[1 2 3]) }
      end

      context '1,, ,2,3,' do
        let(:var) { '1,, ,2,3,' }

        it { is_expected.to eq(%w[1 2 3]) }
      end

      context 'and comma_separated_only is set' do
        subject(:val_to_list) { described_class.val_to_list(var, comma_separated_only: true) }

        context 'value with space' do
          let(:var) { 'value with space' }

          it { is_expected.to eq(['value with space']) }
        end
      end
    end
  end
end
