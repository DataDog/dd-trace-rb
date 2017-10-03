require 'ddtrace/configuration'
require 'ddtrace/configurable'

module Datadog
  class ConfigurationTest < Minitest::Test
    def setup
      @registry = Registry.new
      @configuration = Configuration.new(registry: @registry)
    end

    def test_use_method
      contrib = Minitest::Mock.new
      contrib.expect(:patch, true)

      @registry.add(:example, contrib)
      @configuration.use(:example)

      assert_mock(contrib)
    end

    def test_module_configuration
      integration = Module.new do
        include Contrib::Base
        option :option1
        option :option2
      end

      @registry.add(:example, integration)

      @configuration.use(:example, option1: :foo!, option2: :bar!)

      assert_equal(:foo!, @configuration[:example][:option1])
      assert_equal(:bar!, @configuration[:example][:option2])
    end

    def test_setting_a_configuration_param
      integration = Module.new do
        include Contrib::Base
        option :option1
      end

      @registry.add(:example, integration)
      @configuration[:example][:option1] = :foo
      assert_equal(:foo, @configuration[:example][:option1])
    end

    def test_invalid_integration
      assert_raises(Configuration::InvalidIntegrationError) do
        @configuration[:foobar]
      end
    end

    def test_lazy_option
      integration = Module.new do
        include Contrib::Base
        option :option1, default: -> { 1 + 1 }
      end

      @registry.add(:example, integration)

      assert_equal(2, @configuration[:example][:option1])
    end

    def test_hash_coercion
      integration = Module.new do
        include Contrib::Base
        option :option1, default: :foo
        option :option2, default: :bar
      end

      @registry.add(:example, integration)
      assert_equal({ option1: :foo, option2: :bar }, @configuration[:example].to_h)
    end
  end
end
