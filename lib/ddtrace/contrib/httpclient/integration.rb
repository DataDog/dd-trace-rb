require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/httpclient/configuration/settings'
require 'ddtrace/contrib/configuration/resolvers/pattern_resolver'
require 'ddtrace/contrib/httpclient/patcher'

module Datadog
  module Contrib
    module Httpclient
      # Description of Httpclient integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('2.2.0')

        register_as :httpclient

        def self.version
          Gem.loaded_specs['httpclient'] && Gem.loaded_specs['httpclient'].version
        end

        def self.loaded?
          !defined?(::HTTPClient).nil?
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
