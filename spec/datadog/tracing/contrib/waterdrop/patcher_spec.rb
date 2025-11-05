# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'waterdrop'
require 'datadog'

RSpec.describe 'Waterdrop patcher' do
  before do
    Datadog.configure do |c|
      c.tracing.instrument :waterdrop
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:waterdrop].reset_configuration!
    example.run
    Datadog.registry[:waterdrop].reset_configuration!
  end

  describe 'patch' do
    it 'patches the producer class and adds our middleware to the instance' do
      producer = WaterDrop::Producer.new do |config|
        config.client_class = WaterDrop::Clients::Buffered # Dummy - doesn't try to connect to Kafka
      end

      expect(producer.class).to be < Datadog::Tracing::Contrib::WaterDrop::Producer

      expect(producer.middleware.instance_variable_get(:@steps)).to eq(
        [
          Datadog::Tracing::Contrib::WaterDrop::Middleware
        ]
      )
    end

    context 'when other middleware is present on the producer' do
      let(:dummy_middleware) { ->(message) { message } }
      let(:producer) do
        WaterDrop::Producer.new do |config|
          config.client_class = WaterDrop::Clients::Buffered # Dummy - doesn't try to connect to Kafka
          config.middleware.append(dummy_middleware)
        end
      end

      it 'appends our middleware after existing ones' do
        expect(producer.middleware.instance_variable_get(:@steps)).to eq(
          [
            dummy_middleware,
            Datadog::Tracing::Contrib::WaterDrop::Middleware
          ]
        )
      end
    end

    context 'when our middleware is already present' do
      let(:producer) do
        WaterDrop::Producer.new do |config|
          config.client_class = WaterDrop::Clients::Buffered # Dummy - doesn't try to connect to Kafka
          config.middleware.append(Datadog::Tracing::Contrib::WaterDrop::Middleware)
        end
      end

      it 'does not append it again' do
        expect(producer.middleware.instance_variable_get(:@steps)).to eq(
          [
            Datadog::Tracing::Contrib::WaterDrop::Middleware
          ]
        )
      end
    end

    context 'when DataStreams is enabled' do
      before do
        allow(Datadog::DataStreams).to receive(:enabled?).and_return(true)
      end

      it 'patches without errors' do
        expect do
          WaterDrop::Producer.new do |config|
            config.client_class = WaterDrop::Clients::Buffered
          end
        end.not_to raise_error
      end
    end
  end
end
