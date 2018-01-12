require 'ddtrace/configuration'

module Datadog
  class Configuration
    class PinSetupTest < Minitest::Test
      def setup
        @target = Object.new

        Pin
          .new('original-service', app: 'original-app')
          .onto(@target)
      end

      def test_setting_options
        custom_tracer = get_test_tracer

        custom_options = {
          service_name: 'my-service',
          app: 'my-app',
          app_type: :cache,
          tracer: custom_tracer,
          tags: { env: :prod },
          distributed_tracing: true
        }

        PinSetup.new(@target, custom_options).call

        assert_equal('my-service', @target.datadog_pin.service)
        assert_equal('my-app', @target.datadog_pin.app)
        assert_equal({ env: :prod }, @target.datadog_pin.tags)
        assert_equal({ distributed_tracing: true }, @target.datadog_pin.config)
        assert_equal(custom_tracer, @target.datadog_pin.tracer)
      end

      def test_missing_options_are_not_set
        PinSetup.new(@target, app: 'custom-app').call

        assert_equal('custom-app', @target.datadog_pin.app)
        assert_equal('original-service', @target.datadog_pin.service)
      end

      def test_configure_api
        Datadog.configure(@target, service_name: :foo, extra: :bar)

        assert_equal(:foo, @target.datadog_pin.service)
        assert_equal({ extra: :bar }, @target.datadog_pin.config)
      end
    end
  end
end
