# frozen_string_literal: true
require 'datadog/error_tracking'

RSpec.describe Datadog::ErrorTracking::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  before do
    logger = double(Datadog::Core::Logger)
    allow(logger).to receive(:warn)
    allow(Datadog).to receive(:logger).and_return(logger)
  end

  describe 'error_tracking' do
    context 'programmatic configuration' do
      [
        ['handled_errors', 'all'],
        ['handled_errors', 'user'],
        ['handled_errors', 'third_party'],
        ['handled_errors_include', []],
        ['handled_errors_include', ['foo']],
        ['handled_errors_include', ['foo', 'bar', 'hello', 'world']]
      ].each do |(name, value)|
        context "when #{name} set to #{value}" do
          before do
            settings.error_tracking.public_send("#{name}=", value)
          end

          it 'returns the value back' do
            expect(settings.error_tracking.public_send(name)).to eq(value)
          end
        end
      end
    end

    context 'environment variable configuration' do
      [
        ['DD_ERROR_TRACKING_HANDLED_ERRORS', 'all', 'handled_errors', 'all'],
        ['DD_ERROR_TRACKING_HANDLED_ERRORS', 'user', 'handled_errors', 'user'],
        ['DD_ERROR_TRACKING_HANDLED_ERRORS', 'third_party', 'handled_errors', 'third_party'],
        ['DD_ERROR_TRACKING_HANDLED_ERRORS_INCLUDE', 'foo', 'handled_errors_include', %w[foo]],
        ['DD_ERROR_TRACKING_HANDLED_ERRORS_INCLUDE', 'foo,bar', 'handled_errors_include', %w[foo bar]],
      ].each do |(env_var_name, env_var_value, setting_name, setting_value)|
        context "when #{env_var_name}=#{env_var_value}" do
          around do |example|
            ClimateControl.modify(env_var_name => env_var_value) do
              example.run
            end
          end

          it "sets error_tracking.#{setting_name}=#{setting_value}" do
            expect(settings.error_tracking.public_send(setting_name)).to eq setting_value
          end
        end
      end
    end

    context 'when handled_errors is set to a nil value' do
      before do
        settings.error_tracking.handled_errors = nil
      end

      it 'returns the default value' do
        expect(settings.error_tracking.handled_errors).to eq(Datadog::ErrorTracking::Ext::DEFAULT_HANDLED_ERRORS)
      end
    end

    context 'when handled_errors is set to an invalid value' do
      before do
        settings.error_tracking.handled_errors = 'invalid'
      end

      it 'logs a warning and returns the default value' do
        expect(Datadog.logger).to have_received(:warn).with(
          'Invalid handled errors scope: invalid. ' \
          'Supported values are: all | user | third_party. ' \
          'Deactivating the feature.'
        )
        expect(settings.error_tracking.handled_errors).to eq(Datadog::ErrorTracking::Ext::DEFAULT_HANDLED_ERRORS)
      end
    end
  end
end
