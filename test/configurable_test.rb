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

    def test_custom_setter_block
      @module.class_eval do
        option(:shout) { |value| "#{value.upcase}!" }
      end

      @module.set_option(:shout, 'ouch')
      assert_equal('OUCH!', @module.get_option(:shout))
    end

    def test_invalid_option
      assert_raises(InvalidOptionError) do
        @module.set_option(:bad_option, 'foo')
      end

      assert_raises(InvalidOptionError) do
        @module.get_option(:bad_option)
      end
    end

    def test_to_h
      @module.class_eval do
        option :x, default: 1
        option :y, default: 2
      end

      @module.set_option(:y, 100)
      assert_equal({ x: 1, y: 100 }, @module.to_h)
    end

    def test_false_options
      @module.class_eval do
        option :boolean, default: true
      end

      @module.set_option(:boolean, false)
      refute(@module.get_option(:boolean))
    end

    def test_dependency_solving
      @module.class_eval do
        option :foo, depends_on: [:bar]
        option :bar, depends_on: [:baz]
        option :baz
      end

      assert_equal([:baz, :bar, :foo], @module.sorted_options)
    end
  end
end
