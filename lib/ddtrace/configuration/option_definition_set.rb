require 'ddtrace/configuration/dependency_resolver'

module Datadog
  module Configuration
    # Represents a set of configuration option definitions for an integration
    class OptionDefinitionSet < Hash
      def dependency_order
        DependencyResolver.new(dependency_graph).call
      end

      def dependency_graph
        each_with_object({}) do |(name, option), graph|
          graph[name] = option.depends_on
        end
      end
    end
  end
end
