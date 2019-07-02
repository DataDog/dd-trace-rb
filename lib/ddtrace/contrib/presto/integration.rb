require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/presto/configuration/settings'
require 'ddtrace/contrib/presto/patcher'

module Datadog
  module Contrib
    module Presto
      # Description of Presto integration
      class Integration
        include Contrib::Integration

        register_as :presto

        def self.version
          Gem.loaded_specs['presto-client'] && Gem.loaded_specs['presto-client'].version
        end

        def self.present?
          super && defined?(::Presto::Client::Client)
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
