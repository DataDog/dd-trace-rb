# typed: false
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/grape/configuration/settings'
require 'ddtrace/contrib/grape/patcher'

module Datadog
  module Contrib
    module Grape
      # Description of Grape integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('1.0')

        # @public_api Changing the integration name or integration options can cause breaking changes
        register_as :grape, auto_patch: true

        def self.version
          Gem.loaded_specs['grape'] && Gem.loaded_specs['grape'].version
        end

        def self.loaded?
          !defined?(::Grape).nil? \
            && !defined?(::ActiveSupport::Notifications).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        def new_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
