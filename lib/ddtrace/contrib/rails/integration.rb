require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/rails/configuration/settings'
require 'ddtrace/contrib/rails/patcher'

module Datadog
  module Contrib
    module Rails
      # Metadata of Rails integration
      class Integration
        include Contrib::Integration

        APP = 'sequel'.freeze

        register_as :rails, auto_patch: false

        def self.version
          Gem.loaded_specs['rails'] && Gem.loaded_specs['rails'].version
        end

        def self.present?
          defined?(::Rails)
        end

        def self.compatible?
          return false if ENV['DISABLE_DATADOG_RAILS']
          super && defined?(::Rails::VERSION) && ::Rails::VERSION::MAJOR.to_i >= 3
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

require 'ddtrace/contrib/rails/railtie' if Datadog.registry[:rails].class.compatible?
