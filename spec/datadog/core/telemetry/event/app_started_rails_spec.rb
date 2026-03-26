require 'datadog/tracing/contrib/support/spec_helper'
require 'rails'
require 'datadog/core/telemetry/event/app_started'
require 'datadog/tracing/contrib/rails/integration'

RSpec.describe Datadog::Core::Telemetry::Event::AppStarted do
  subject(:event) { described_class.new(components: Datadog.send(:components)) }

  around do |example|
    Datadog.registry[:rails].reset_configuration!
    Datadog.shutdown!
    Datadog.configuration.reset!
    example.run
    Datadog.registry[:rails].reset_configuration!
    Datadog.shutdown!
    Datadog.configuration.reset!
  end

  describe '.payload' do
    it 'reports instrumented Rails configuration' do
      Datadog.configure do |c|
        c.tracing.instrument :rails, middleware_names: true
        c.tracing.instrument :active_support
      end

      expect(event.payload[:configuration]).to include(
        name: 'tracing.rails.middleware_names',
        origin: 'code',
        seq_id: 5,
        value: true,
      )
      expect(event.payload[:configuration]).to include(
        name: 'tracing.rails.middleware_names',
        origin: 'default',
        seq_id: 1,
        value: false,
      )
      # When Rails is instrumented, the enabled option is set to true by default
      expect(event.payload[:configuration]).to include(
        name: 'DD_TRACE_RAILS_ENABLED',
        origin: 'default',
        seq_id: 1,
        value: true,
      )
      # This is the only option that is located in a settings block for any contrib
      expect(event.payload[:configuration]).to include(
        name: 'tracing.active_support.cache_key.enabled',
        origin: 'default',
        seq_id: 1,
        value: true,
      )
    end
  end
end
