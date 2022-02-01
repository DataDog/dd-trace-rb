# typed: false
require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/excon/configuration/settings'
require 'datadog/tracing/contrib/configuration/resolvers/pattern_resolver'
require 'datadog/tracing/contrib/excon/patcher'

module Datadog
  module Tracing
    module Contrib
      module Excon
        # Description of Excon integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('0.50.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :excon

          def self.version
            Gem.loaded_specs['excon'] && Gem.loaded_specs['excon'].version
          end

          def self.loaded?
            !defined?(::Excon).nil?
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

          def resolver
            @resolver ||= Contrib::Configuration::Resolvers::PatternResolver.new
          end
        end
      end
    end
  end
end
