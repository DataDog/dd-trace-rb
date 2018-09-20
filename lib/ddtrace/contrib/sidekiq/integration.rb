require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/sidekiq/configuration/settings'
require 'ddtrace/contrib/sidekiq/patcher'

module Datadog
  module Contrib
    module Sidekiq
      # Description of Sidekiq integration
      class Integration
        include Contrib::Integration

        register_as :sidekiq

        def self.version
          Gem.loaded_specs['sidekiq'] && Gem.loaded_specs['sidekiq'].version
        end

        def self.present?
          super && defined?(::Sidekiq)
        end

        def self.compatible?
          super && version >= Gem::Version.new('4.0.0')
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
