# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'

require 'ruby-kafka'
require 'active_support'
require 'datadog'

RSpec.describe 'Kafka patcher with tracing disabled' do
  # The patcher only patches once per process; reset the guard so `patch` runs
  # again against this example's configuration.
  before { Datadog::Tracing::Contrib::Kafka::Patcher.instance_variable_set(:@patch_only_once, nil) }

  after do
    Datadog.registry[:kafka].reset_configuration!
    without_warnings { Datadog.configuration.reset! }
  end

  context 'when kafka tracing is disabled but Data Streams Monitoring is enabled' do
    it 'still applies the Data Streams Monitoring instrumentation' do
      Datadog.configure do |c|
        c.data_streams.enabled = true
        c.tracing.instrument :kafka, enabled: false
      end

      expect(::Kafka::Producer.ancestors).to include(Datadog::Tracing::Contrib::Kafka::Instrumentation::Producer)
      expect(::Kafka::Consumer.ancestors).to include(Datadog::Tracing::Contrib::Kafka::Instrumentation::Consumer)
    end

    it 'does not create tracing spans for Kafka events' do
      Datadog.configure do |c|
        c.data_streams.enabled = true
        c.tracing.instrument :kafka, enabled: false
      end

      expect(Datadog::Tracing).to_not receive(:trace)

      ActiveSupport::Notifications.instrument('deliver_messages.producer.kafka', client_id: 'test-client') {}
    end

    it 'resumes creating tracing spans if Kafka tracing is enabled later at runtime' do
      Datadog.configure do |c|
        c.data_streams.enabled = true
        c.tracing.instrument :kafka, enabled: false
      end

      Datadog.configure { |c| c.tracing.instrument :kafka, enabled: true }

      expect(Datadog::Tracing).to receive(:trace).and_call_original

      ActiveSupport::Notifications.instrument('deliver_messages.producer.kafka', client_id: 'test-client') {}
    end
  end

  context 'when both kafka tracing and Data Streams Monitoring are disabled' do
    it 'does not patch the integration at all' do
      # Neither tracing spans nor DSM instrumentation should be installed, so the
      # patcher never runs and never subscribes to events.
      expect(Datadog::Tracing::Contrib::Kafka::Events).to_not receive(:subscribe!)

      Datadog.configure do |c|
        c.data_streams.enabled = false
        c.tracing.instrument :kafka, enabled: false
      end

      expect(Datadog::Tracing::Contrib::Kafka::Patcher.patched?).to be(false)
    end
  end
end
