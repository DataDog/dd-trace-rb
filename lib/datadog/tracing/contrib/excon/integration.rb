require_relative '../integration'
require_relative 'configuration/settings'
require_relative '../configuration/resolvers/pattern_resolver'
require_relative 'patcher'

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
