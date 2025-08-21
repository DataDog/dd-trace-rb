# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'climate_control'

RSpec.describe 'Kafka Data Streams Monitoring configuration' do
  describe 'DD_DATA_STREAMS_ENABLED environment variable' do
    after do
      # Reset configuration after each test
      Datadog.registry[:kafka].reset_configuration! if Datadog.registry[:kafka]
    end

    context 'when DD_DATA_STREAMS_ENABLED=true' do
      it 'enables data streams monitoring' do
        ClimateControl.modify('DD_DATA_STREAMS_ENABLED' => 'true') do
          Datadog.configure do |c|
            c.tracing.instrument :kafka
          end

          expect(Datadog.configuration.tracing.data_streams.enabled).to be true
        end
      end
    end

    context 'when DD_DATA_STREAMS_ENABLED=false' do
      it 'disables data streams monitoring' do
        ClimateControl.modify('DD_DATA_STREAMS_ENABLED' => 'false') do
          Datadog.configure do |c|
            c.tracing.instrument :kafka
          end

          expect(Datadog.configuration.tracing.data_streams.enabled).to be false
        end
      end
    end

    context 'when DD_DATA_STREAMS_ENABLED=1' do
      it 'enables data streams monitoring' do
        ClimateControl.modify('DD_DATA_STREAMS_ENABLED' => '1') do
          Datadog.configure do |c|
            c.tracing.instrument :kafka
          end

          expect(Datadog.configuration.tracing.data_streams.enabled).to be true
        end
      end
    end

    context 'when DD_DATA_STREAMS_ENABLED=0' do
      it 'disables data streams monitoring' do
        ClimateControl.modify('DD_DATA_STREAMS_ENABLED' => '0') do
          Datadog.configure do |c|
            c.tracing.instrument :kafka
          end

          expect(Datadog.configuration.tracing.data_streams.enabled).to be false
        end
      end
    end

    context 'when DD_DATA_STREAMS_ENABLED is not set' do
      it 'defaults to disabled' do
        Datadog.configure do |c|
          c.tracing.instrument :kafka
        end

        expect(Datadog.configuration.tracing.data_streams.enabled).to be false
      end
    end
  end

  describe 'programmatic configuration' do
    after do
      Datadog.registry[:kafka].reset_configuration! if Datadog.registry[:kafka]
    end

    it 'can be enabled programmatically' do
      Datadog.configure do |c|
        c.tracing.instrument :kafka
        c.tracing.data_streams.enabled = true
      end

      expect(Datadog.configuration.tracing.data_streams.enabled).to be true
    end

    it 'can be disabled programmatically' do
      Datadog.configure do |c|
        c.tracing.instrument :kafka
        c.tracing.data_streams.enabled = false
      end

      expect(Datadog.configuration.tracing.data_streams.enabled).to be false
    end
  end
end

