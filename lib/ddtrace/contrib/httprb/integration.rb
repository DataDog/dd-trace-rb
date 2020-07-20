require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/httprb/configuration/settings'
require 'ddtrace/contrib/configuration/resolvers/pattern_resolver'
require 'ddtrace/contrib/httprb/patcher'

module Datadog
  module Contrib
    module Httprb
      # Description of Httprb integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('2.0.0')

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

        def default_configuration
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
