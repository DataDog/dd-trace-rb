require 'datadog/tracing/contrib/support/spec_helper'

require 'redis'
require 'ddtrace'

require_relative './shared_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'
require 'datadog/tracing/contrib/span_attribute_schema_examples'
require 'datadog/tracing/contrib/peer_service_configuration_examples'

RSpec.describe 'Redis test' do
  let(:configuration_options) { {} }
  let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }
  let(:default_redis_options) { { host: host, port: port, driver: driver } }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :redis, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:redis].reset_configuration!
    example.run
    Datadog.registry[:redis].reset_configuration!
  end

  context 'with ruby driver' do
    let(:driver) { :ruby }

    context 'with standard configuration' do
      let(:redis_options) { default_redis_options }
      let(:redis) { Redis.new(redis_options.freeze) }

      it_behaves_like 'environment service name', 'DD_TRACE_REDIS_SERVICE_NAME' do
        subject { redis.ping }
      end

      it_behaves_like 'configured peer service span', 'DD_TRACE_REDIS_PEER_SERVICE' do
        subject { redis.ping }
      end

      it_behaves_like 'schema version span' do
        subject { redis.ping }
      end

      context 'with default settings' do
        let(:configuration_options) { {} }

        it_behaves_like 'redis instrumentation'
        it_behaves_like 'an authenticated redis instrumentation'
      end

      context 'with service_name as `standard`' do
        let(:configuration_options) { { service_name: 'standard' } }

        it_behaves_like 'redis instrumentation', service_name: 'standard'
        it_behaves_like 'an authenticated redis instrumentation', service_name: 'standard'
      end

      context 'with command_args as `true`' do
        let(:configuration_options) { { command_args: true } }

        it_behaves_like 'redis instrumentation', command_args: true
        it_behaves_like 'an authenticated redis instrumentation', command_args: true
      end
    end

    context 'with custom configuration at the instance level' do
      let(:redis) { Redis.new(redis_options.freeze) }

      context(
        'when working with Redis < 5',
        skip: Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('5.0.0')
      ) do
        context 'when supplying custom configuration via `Datadog.configure_onto`' do
          before { Datadog.configure_onto(redis, **tracing_options) }

          let(:redis_options) { default_redis_options }

          context 'with service_name as `custom`' do
            let(:tracing_options) { { service_name: 'custom' } }

            it_behaves_like 'redis instrumentation', service_name: 'custom'
            it_behaves_like 'an authenticated redis instrumentation', service_name: 'custom'
          end

          context 'with command_args as `true`' do
            let(:tracing_options) { { command_args: true } }

            it_behaves_like 'redis instrumentation', command_args: true
            it_behaves_like 'an authenticated redis instrumentation', command_args: true
          end
        end
      end

      context(
        'when working with Redis >= 5',
        skip: Gem::Version.new(::Redis::VERSION) < Gem::Version.new('5.0.0')
      ) do
        context 'when attempting to supply configuration via Datadog.configure_onto' do
          let(:redis_options) { default_redis_options }

          it 'logs a warning about non-supported usage of Datadog.configure_onto' do
            expect(Datadog.logger)
              .to receive(:warn)
              .with(/`Datadog\.configure_onto\(redis\)` is not supported on Redis 5+/)
            Datadog.configure_onto(redis, service_name: 'custom')
          end
        end

        context 'when supplying custom configuration via Redis 5 custom API' do
          let(:redis_options) do
            default_redis_options.merge(custom: { datadog: tracing_options })
          end

          context 'with service_name as `custom`' do
            let(:tracing_options) { { service_name: 'custom' } }

            it_behaves_like 'redis instrumentation', service_name: 'custom'
            it_behaves_like 'an authenticated redis instrumentation', service_name: 'custom'
          end

          context 'with command_args as `true`' do
            let(:tracing_options) { { command_args: true } }

            it_behaves_like 'redis instrumentation', command_args: true
            it_behaves_like 'an authenticated redis instrumentation', command_args: true
          end
        end
      end
    end
  end
end
