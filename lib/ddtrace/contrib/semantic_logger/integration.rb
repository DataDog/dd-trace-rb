require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/semantic_logger/configuration/settings'
require 'ddtrace/contrib/semantic_logger/patcher'

module Datadog
  module Contrib
    module SemanticLogger
      # Description of SemanticLogger integration
      class Integration
        include Contrib::Integration

        # v4 had a migration to `named_tags` instead of `payload`
        # and has been out for almost 5 years at this point
        # it's probably reasonable to nudge users to using modern ruby libs
        MINIMUM_VERSION = Gem::Version.new('4.0.0')

        register_as :semantic_logger

        def self.version
          Gem.loaded_specs['semantic_logger'] && Gem.loaded_specs['semantic_logger'].version
        end

        def self.loaded?
          !defined?(::SemanticLogger::Logger).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        # TODO: abstract out the log injection related instrumentation into it's own module so we dont
        # keep having to do these workarounds
        def auto_instrument?
          false
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
