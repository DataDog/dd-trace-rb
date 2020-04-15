require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/resque/configuration/settings'
require 'ddtrace/contrib/resque/patcher'

module Datadog
  module Contrib
    module Resque
      # Description of Resque integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('1.0')
        # Maximum is first version it's NOT compatible with (not inclusive)
        MAXIMUM_VERSION = Gem::Version.new('2.0')

        register_as :resque, auto_patch: true

        def self.version
          Gem.loaded_specs['resque'] && Gem.loaded_specs['resque'].version
        end

        def self.loaded?
          !defined?(::Resque).nil?
        end

        def self.compatible?
          super \
            && version >= Gem::Version.new('1.0') \
            && version < MAXIMUM_VERSION
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
