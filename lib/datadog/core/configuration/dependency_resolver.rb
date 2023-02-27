require 'tsort'

module Datadog
  module Core
    module Configuration
      # Resolver performs a topological sort over the dependency graph
      class DependencyResolver
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
end
