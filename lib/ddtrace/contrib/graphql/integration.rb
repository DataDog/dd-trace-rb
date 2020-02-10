require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/graphql/configuration/settings'
require 'ddtrace/contrib/graphql/patcher'

module Datadog
  module Contrib
    module GraphQL
      # Description of GraphQL integration
      class Integration
        include Contrib::Integration

        register_as :graphql, auto_patch: true

        def self.version
          Gem.loaded_specs['graphql'] && Gem.loaded_specs['graphql'].version
        end

        def self.loaded?
          defined?(::GraphQL) && defined?(::GraphQL::Tracing::DataDogTracing)
        end

        def self.compatible?
          super && version >= Gem::Version.new('1.7.9')
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
