require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/presto/configuration/settings'
require 'ddtrace/contrib/presto/patcher'

module Datadog
  module Contrib
    module Presto
      # Description of Presto integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('0.5.14')

        register_as :presto

        def self.version
          Gem.loaded_specs['presto-client'] && Gem.loaded_specs['presto-client'].version
        end

        def self.loaded?
          !defined?(::Presto::Client::Client).nil?
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
