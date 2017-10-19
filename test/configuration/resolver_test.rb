require 'ddtrace/configuration'

module Datadog
  class Configuration
    class ResolverTest < Minitest::Test
      def test_dependency_solving
        graph = { 1 => [2], 2 => [3, 4], 3 => [], 4 => [3], 5 => [1] }
        tsort = Resolver.new(graph).call

        assert_equal([3, 4, 2, 1, 5], tsort)
      end

      def test_cyclic_dependecy
        graph = { 1 => [2], 2 => [1] }

        assert_raises(TSort::Cyclic) do
          Resolver.new(graph).call
        end
      end
    end
  end
end
