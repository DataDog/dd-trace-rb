require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/aws/configuration/settings'
require 'ddtrace/contrib/aws/patcher'

module Datadog
  module Contrib
    module Aws
      # Description of AWS integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('2.0')

        register_as :aws, auto_patch: true

        def self.version
          if Gem.loaded_specs['aws-sdk']
            Gem.loaded_specs['aws-sdk'].version
          elsif Gem.loaded_specs['aws-sdk-core']
            Gem.loaded_specs['aws-sdk-core'].version
          end
        end

        def self.loaded?
          !defined?(::Seahorse::Client::Base).nil?
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
      end
    end
  end
end
