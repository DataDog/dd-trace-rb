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
      [
        'true',
        'TRUE',
        '1',
        ' 1 ',
      ].each do |value|
        context "'#{value}'" do
          let(:env_value) { value }

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
          let(:env_value) { value }

          it { is_expected.to be false }
        end
      end

      include_context 'with deprecated options'
    end
  end
end
