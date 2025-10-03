# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'

# FFI::Function background native thread
ThreadHelpers.with_leaky_thread_creation(:rdkafka) do
  require 'waterdrop'
end
require 'datadog'

RSpec.describe 'WaterDrop middleware' do
  before do
    Datadog.configure do |c|
      c.tracing.instrument :waterdrop, tracing_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:waterdrop].reset_configuration!
    example.run
    Datadog.registry[:waterdrop].reset_configuration!
  end

  subject(:middleware) { Datadog::Tracing::Contrib::WaterDrop::Middleware }

  let(:producer) do
    WaterDrop::Producer.new do |config|
      # Dummy - doesn't try to connect to Kafka
      config.client_class = WaterDrop::Clients::Buffered
    end
  end

  let(:tracing_options) { { distributed_tracing: false } }

  describe '.instrument' do
    context 'when distributed tracing is disabled' do
      it 'does not propagate trace context in message headers' do
        message_1 = { topic: 'topic_name', payload: 'foo' }
        Datadog::Tracing.trace('test.span') do
          middleware.call(message_1)
        end

        expect(message_1[:headers]).to be_nil
      end
    end

    context 'when distributed tracing is enabled' do
      let(:tracing_options) { { distributed_tracing: true } }

      it 'propagates trace context in message headers' do
        message = { topic: 'topic_name', payload: 'foo' }
        Datadog::Tracing.trace('test.span') do
          middleware.call(message)
        end

        expect(message[:headers]).to include(
          'x-datadog-trace-id' => low_order_trace_id(span.trace_id).to_s,
          'x-datadog-parent-id' => span.id.to_s
        )
      end
    end
  end
end
