# typed: false

require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/httprb/configuration/settings'
require 'datadog/tracing/contrib/configuration/resolvers/pattern_resolver'
require 'datadog/tracing/contrib/httprb/patcher'

module Datadog
  module Tracing
    module Contrib
      module Httprb
        # Description of Httprb integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('2.0.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :httprb

          def self.version
            Gem.loaded_specs['http'] && Gem.loaded_specs['http'].version
          end

          def self.loaded?
            !defined?(::HTTP).nil? && !defined?(::HTTP::Client).nil?
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
