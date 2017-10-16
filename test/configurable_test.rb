require 'ddtrace/configurable'

module Datadog
  class ConfigurableTest < Minitest::Test
    def setup
      @module = Module.new { include(Configurable) }
    end

    def test_option_methods
      assert_respond_to(@module, :set_option)
      assert_respond_to(@module, :get_option)
    end

    def test_option_default
      @module.class_eval do
        option :foo, default: :bar
      end

      assert_equal(:bar, @module.get_option(:foo))
    end

    def test_setting_an_option
      @module.class_eval do
        option :foo, default: :bar
      end

      @module.set_option(:foo, 'baz!')
      assert_equal('baz!', @module.get_option(:foo))
    end

    def test_custom_setter
      @module.class_eval do
        option :shout, setter: ->(v) { v.upcase }
      end

      @module.set_option(:shout, 'loud')
      assert_equal('LOUD', @module.get_option(:shout))
    end

    def test_invalid_option
      assert_raises(InvalidOptionError) do
        @module.set_option(:bad_option, 'foo')
      end

      assert_raises(InvalidOptionError) do
        @module.get_option(:bad_option)
      end
    end

    def test_merge_configuration
      klass = Class.new do
        include Configurable
        option :x, default: :default_x
        option :y, default: :default_y

        attr_reader :options

        def initialize(options = {})
          @options = merge_configuration(options)
        end
      end

      instance = klass.new(x: :custom_x, z: :custom_z)

      assert_equal(:custom_x, instance.options[:x])
      assert_equal(:default_y, instance.options[:y])
      assert_equal(:custom_z, instance.options[:z])
    end

    def test_to_h
      @module.class_eval do
        option :x, default: 1
        option :y, default: 2
      end

      @module.set_option(:y, 100)
      assert_equal({ x: 1, y: 100 }, @module.to_h)
    end
  end
end
