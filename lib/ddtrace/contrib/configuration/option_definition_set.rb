require 'ddtrace/configuration/resolver'

module Datadog
  module Contrib
    module Configuration
      # Represents a set of configuration option definitions for an integration
      class OptionDefinitionSet < Hash
        def dependency_order
          Datadog::Configuration::Resolver.new(dependency_graph).call
        end

        def dependency_graph
          each_with_object({}) do |(name, option), graph|
            graph[name] = option.depends_on
          end
        end
      end
    end
  end
end
