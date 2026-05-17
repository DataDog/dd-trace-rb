# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Datadog::AppSec::Env do
  describe '.disable_appsec_on_lambda!' do
    subject(:disable_appsec_on_lambda) { described_class.disable_appsec_on_lambda! }

    context 'when AWS_LAMBDA_FUNCTION_NAME is not set' do
      around do |example|
        ClimateControl.modify('DD_APPSEC_ENABLED' => 'true') do
          example.run
        end
      end

      it 'does not change DD_APPSEC_ENABLED' do
        disable_appsec_on_lambda

        expect(ENV['DD_APPSEC_ENABLED']).to eq('true')
      end
    end

    context 'when AWS_LAMBDA_FUNCTION_NAME is set' do
      around do |example|
        ClimateControl.modify(
          'AWS_LAMBDA_FUNCTION_NAME' => 'my-function',
          'DD_APPSEC_ENABLED' => 'true',
        ) do
          example.run
        end
      end

      it 'sets DD_APPSEC_ENABLED to false' do
        disable_appsec_on_lambda

        expect(ENV['DD_APPSEC_ENABLED']).to eq('false')
      end
    end
  end
end
