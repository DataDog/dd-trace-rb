require 'spec_helper'

require 'securerandom'
require 'ddtrace'

RSpec.describe Datadog::Configuration::ProxyPin do
  subject(:proxy_pin) { described_class.new(proxy) }

  let(:patcher) do
    stub_const('TestIntegration', Class.new do
      include Datadog::Contrib::Base
      register_as :test_integration
    end)
  end

  let(:proxy) do
    patcher; Datadog.configuration[:test_integration]
  end

  context 'when configuration defines the option' do
    Datadog::Configuration::ProxyPin::OPTIONS.each do |option|
      describe do
        let(:old_value) { SecureRandom.uuid }

        before(:each) do
          # Define the option on the class
          patcher.send(:option, option)

          # Set a value for the option
          Datadog.configuration[:test_integration][option] = old_value
        end

        describe "\##{option}" do
          subject(:result) { proxy_pin.send(option) }
          it { is_expected.to eq(old_value) }
        end

        describe "\##{option}=" do
          subject(:result) { proxy_pin.send("#{option}=", value) }
          let(:value) { SecureRandom.uuid }
          it { is_expected.to eq(value) }
        end
      end
    end
  end

  context 'when configuration does not define the option' do
    Datadog::Configuration::ProxyPin::OPTIONS.each do |option|
      describe do
        describe "\##{option}" do
          subject(:result) { proxy_pin.send(option) }
          it { is_expected.to be nil }

          context 'after a value is set' do
            before(:each) { proxy_pin.send("#{option}=", value) }
            let(:value) { SecureRandom.uuid }
            it { is_expected.to eq(value) }
          end
        end

        describe "\##{option}=" do
          subject(:result) { proxy_pin.send("#{option}=", value) }
          let(:value) { SecureRandom.uuid }
          it { is_expected.to eq(value) }
        end
      end
    end
  end
end
