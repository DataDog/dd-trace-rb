require 'spec_helper'

require 'ddtrace/environment'

RSpec.describe Datadog::Environment do
  let(:var) { 'TEST_VAR' }

  shared_context 'env var' do
    around do |example|
      ClimateControl.modify(var => env_value) do
        example.run
      end
    end
  end

  describe '::env_to_bool' do
    subject(:env_to_bool) { described_class.env_to_bool(var) }

    context 'when env var is not defined' do
      context 'and default is not defined' do
        it { is_expected.to be nil }
      end

      context 'and default is defined' do
        subject(:env_to_bool) { described_class.env_to_bool(var, default) }
        let(:default) { double('default') }
        it { is_expected.to be default }
      end
    end

    context 'when env var is set as' do
      include_context 'env var'

      # True values
      %w[
        true
        TRUE
      ].each do |value|
        context value.to_s do
          let(:env_value) { value.to_s }
          it { is_expected.to be true }
        end
      end

      # False values
      [
        '',
        'false',
        'FALSE',
        0,
        1
      ].each do |value|
        context value.to_s do
          let(:env_value) { value.to_s }
          it { is_expected.to be false }
        end
      end
    end
  end

  describe '::env_to_int' do
    subject(:env_to_int) { described_class.env_to_int(var) }

    context 'when env var is not defined' do
      context 'and default is not defined' do
        it { is_expected.to be nil }
      end

      context 'and default is defined' do
        subject(:env_to_int) { described_class.env_to_int(var, default) }
        let(:default) { double('default') }
        it { is_expected.to be default }
      end
    end

    context 'when env var is set as' do
      include_context 'env var'

      context '0' do
        let(:env_value) { '0' }
        it { is_expected.to eq 0 }
      end

      context '1' do
        let(:env_value) { '1' }
        it { is_expected.to eq 1 }
      end

      context '1.5' do
        let(:env_value) { '1.5' }
        it { is_expected.to eq 1 }
      end

      context 'test' do
        let(:env_value) { 'test' }
        it { is_expected.to eq 0 }
      end
    end
  end

  describe '::env_to_float' do
    subject(:env_to_float) { described_class.env_to_float(var) }

    context 'when env var is not defined' do
      context 'and default is not defined' do
        it { is_expected.to be nil }
      end

      context 'and default is defined' do
        subject(:env_to_float) { described_class.env_to_float(var, default) }
        let(:default) { double('default') }
        it { is_expected.to be default }
      end
    end

    context 'when env var is set as' do
      include_context 'env var'

      context '0' do
        let(:env_value) { '0' }
        it { is_expected.to eq 0.0 }
      end

      context '1' do
        let(:env_value) { '1' }
        it { is_expected.to eq 1.0 }
      end

      context '1.5' do
        let(:env_value) { '1.5' }
        it { is_expected.to eq 1.5 }
      end

      context 'test' do
        let(:env_value) { 'test' }
        it { is_expected.to eq 0.0 }
      end
    end
  end

  describe '::env_to_list' do
    subject(:env_to_list) { described_class.env_to_list(var) }

    context 'when env var is not defined' do
      context 'and default is not defined' do
        it { is_expected.to eq([]) }
      end

      context 'and default is defined' do
        subject(:env_to_list) { described_class.env_to_list(var, default) }
        let(:default) { double('default') }
        it { is_expected.to be default }
      end
    end

    context 'when env var is set as' do
      include_context 'env var'

      context '\'\'' do
        let(:env_value) { '' }
        it { is_expected.to eq([]) }
      end

      context ',' do
        let(:env_value) { ',' }
        it { is_expected.to eq([]) }
      end

      context '1' do
        let(:env_value) { '1' }
        it { is_expected.to eq(['1']) }
      end

      context '1,2' do
        let(:env_value) { '1,2' }
        it { is_expected.to eq(%w[1 2]) }
      end

      context ' 1 , 2 , 3 ' do
        let(:env_value) { ' 1 , 2 , 3 ' }
        it { is_expected.to eq(%w[1 2 3]) }
      end
    end
  end
end
