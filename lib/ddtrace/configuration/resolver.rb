require 'tsort'

module Datadog
  class Configuration
    # Resolver performs a topological sort over the dependency graph
    class Resolver
      include TSort

      def initialize(dependency_graph = {})
        @dependency_graph = dependency_graph
      end

      def tsort_each_node(&blk)
        @dependency_graph.each_key(&blk)
      end

      def tsort_each_child(node, &blk)
        @dependency_graph.fetch(node).each(&blk)
      end

      alias call tsort
    end
  end
end
