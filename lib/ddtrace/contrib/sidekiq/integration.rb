require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/sidekiq/configuration/settings'
require 'ddtrace/contrib/sidekiq/patcher'

module Datadog
  module Contrib
    module Sidekiq
      # Description of Sidekiq integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('3.5.4')

        register_as :sidekiq

        def self.version
          Gem.loaded_specs['sidekiq'] && Gem.loaded_specs['sidekiq'].version
        end

        def self.loaded?
          !defined?(::Sidekiq).nil?
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
