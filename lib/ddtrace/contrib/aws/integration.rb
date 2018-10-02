require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/aws/configuration/settings'
require 'ddtrace/contrib/aws/patcher'

module Datadog
  module Contrib
    module Aws
      # Description of AWS integration
      class Integration
        include Contrib::Integration

        register_as :aws, auto_patch: true

        def self.version
          Gem.loaded_specs['aws-sdk'] && Gem.loaded_specs['aws-sdk'].version
        end

        def self.present?
          super && defined?(::Seahorse::Client::Base)
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
