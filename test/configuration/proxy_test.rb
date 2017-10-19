require 'ddtrace/configurable'

module Datadog
  class Configuration
    class ProxyTest < Minitest::Test
      def setup
        @module = Module.new do
          include Configurable
          option :x, default: :a
          option :y, default: :b
        end

        @proxy = Proxy.new(@module)
      end

      def test_hash_syntax
        @proxy[:x] = 1
        @proxy[:y] = 2

        assert_equal(1, @proxy[:x])
        assert_equal(2, @proxy[:y])
      end

      def test_hash_coercion
        assert_equal({ x: :a, y: :b }, @proxy.to_h)
        assert_equal({ x: :a, y: :b }, @proxy.to_hash)
      end

      def test_merge
        assert_equal({ x: :a, y: :b, z: :c }, @proxy.merge(z: :c))
      end
    end
  end
end
