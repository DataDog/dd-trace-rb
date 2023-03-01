require 'spec_helper'

require 'datadog/core/environment/variable_helpers'

RSpec.describe Datadog::Core::Environment::VariableHelpers do
  let(:variable_helpers) { Class.new { extend Datadog::Core::Environment::VariableHelpers } }
  let(:env_key) { var }
  let(:var) { 'TEST_VAR' }
  let(:options) { {} }

  shared_context 'env var' do
    around do |example|
      ClimateControl.modify(env_key => env_value) do
        example.run
      end
    end
  end

  shared_context 'with deprecated options' do
    # rubocop:disable RSpec/NamedSubject
    context 'with deprecated environment variables' do
      let(:env_key) { 'key-deprecated' }
      let(:var) { %w[key key-deprecated] }
      let(:env_value) { 'value' }

      context 'and deprecation_warning option is true' do
        let(:options) { { deprecation_warning: true } }

        it 'records to deprecation log' do
          expect { subject }.to log_deprecation(include('key-deprecated'))
        end
      end

      context 'and deprecation_warning option is false' do
        let(:options) { { deprecation_warning: false } }

        it 'does not record to deprecation log' do
          expect { subject }.to_not log_deprecation
        end
      end

      context 'and deprecation_warning option the default' do
        it 'records to deprecation log' do
          expect { subject }.to log_deprecation(include('key-deprecated'))
        end
      end
    end
    # rubocop:enable RSpec/NamedSubject
  end

  describe '::env_to_bool' do
    subject(:env_to_bool) { variable_helpers.env_to_bool(var, **options) }

    context 'when env var is not defined' do
      context 'and default is not defined' do
        it { is_expected.to be nil }
      end

      context 'and default is defined' do
        subject(:env_to_bool) { variable_helpers.env_to_bool(var, default) }

        let(:default) { double }

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

      include_context 'with deprecated options'
    end
  end

  describe '::env_to_int' do
    subject(:env_to_int) { variable_helpers.env_to_int(var, **options) }

    context 'when env var is not defined' do
      context 'and default is not defined' do
        it { is_expected.to be nil }
      end

      context 'and default is defined' do
        subject(:env_to_int) { variable_helpers.env_to_int(var, default) }

        let(:default) { double }

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

      include_context 'with deprecated options'
    end
  end

  describe '::env_to_float' do
    subject(:env_to_float) { variable_helpers.env_to_float(var, **options) }

    context 'when env var is not defined' do
      context 'and default is not defined' do
        it { is_expected.to be nil }
      end

      context 'and default is defined' do
        subject(:env_to_float) { variable_helpers.env_to_float(var, default) }

        let(:default) { double }

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

      include_context 'with deprecated options'
    end
  end

  describe '::env_to_list' do
    subject(:env_to_list) { variable_helpers.env_to_list(var, comma_separated_only: false, **options) }

    context 'when env var is not defined' do
      context 'and default is not defined' do
        it { is_expected.to eq([]) }
      end

      context 'and default is defined' do
        subject(:env_to_list) { variable_helpers.env_to_list(var, default, comma_separated_only: false) }

        let(:default) { double }

        it { is_expected.to be default }
      end
    end

    context 'when env var is set' do
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

      context ' 1 , 2 ,  3 ' do
        let(:env_value) { ' 1 , 2 ,  3 ' }

        it { is_expected.to eq(%w[1 2 3]) }
      end

      context '1 2 3' do
        let(:env_value) { '1 2 3' }

        it { is_expected.to eq(%w[1 2 3]) }
      end

      context '1,2 3' do
        let(:env_value) { '1,2 3' }

        it { is_expected.to eq(['1', '2 3']) }
      end

      context ' 1  2   3 ' do
        let(:env_value) { ' 1  2   3 ' }

        it { is_expected.to eq(%w[1 2 3]) }
      end

      context '1,, ,2,3,' do
        let(:env_value) { '1,, ,2,3,' }

        it { is_expected.to eq(%w[1 2 3]) }
      end

      context 'and comma_separated_only is set' do
        subject(:env_to_list) { variable_helpers.env_to_list(var, comma_separated_only: true) }

        context 'value with space' do
          let(:env_value) { 'value with space' }

          it { is_expected.to eq(['value with space']) }
        end
      end

      include_context 'with deprecated options'
    end
  end
end
