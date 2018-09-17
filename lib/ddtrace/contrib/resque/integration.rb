require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/resque/configuration/settings'
require 'ddtrace/contrib/resque/patcher'

module Datadog
  module Contrib
    module Resque
      # Description of Resque integration
      class Integration
        include Contrib::Integration

        APP = 'resque'.freeze

        register_as :resque, auto_patch: true

        def self.version
          Gem.loaded_specs['resque'] && Gem.loaded_specs['resque'].version
        end

        def self.present?
          super && defined?(::Resque)
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end

        class << self
          # Globally-acccesible reference for pre-forking optimization
          attr_accessor :sync_writer
        end
      end
    end
  end
end
