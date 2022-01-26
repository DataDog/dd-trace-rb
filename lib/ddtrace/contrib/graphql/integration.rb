# typed: false
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/graphql/configuration/settings'
require 'ddtrace/contrib/graphql/patcher'

module Datadog
  module Contrib
    module GraphQL
      # Description of GraphQL integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('1.7.9')

        # @public_api Changing the integration name or integration options can cause breaking changes
        register_as :graphql, auto_patch: true

        def self.version
          Gem.loaded_specs['graphql'] && Gem.loaded_specs['graphql'].version
        end

        def self.loaded?
          !defined?(::GraphQL).nil? \
            && !defined?(::GraphQL::Tracing::DataDogTracing).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        def new_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
