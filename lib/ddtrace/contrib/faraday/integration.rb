require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/configuration/resolvers/pattern_resolver'
require 'ddtrace/contrib/faraday/configuration/settings'
require 'ddtrace/contrib/faraday/patcher'

module Datadog
  module Contrib
    module Faraday
      # Description of Faraday integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('0.14.0')

        register_as :faraday, auto_patch: true

        def self.version
          Gem.loaded_specs['faraday'] && Gem.loaded_specs['faraday'].version
        end

        def self.loaded?
          !defined?(::Faraday).nil?
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
