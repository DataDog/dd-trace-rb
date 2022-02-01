# typed: false
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/active_support/configuration/settings'
require 'ddtrace/contrib/active_support/patcher'
require 'ddtrace/contrib/active_support/cache/redis'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module ActiveSupport
      # Describes the ActiveSupport integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('3.2')

        # @public_api Changing the integration name or integration options can cause breaking changes
        register_as :active_support, auto_patch: false

        def self.version
          Gem.loaded_specs['activesupport'] && Gem.loaded_specs['activesupport'].version
        end

        def self.loaded?
          !defined?(::ActiveSupport).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        # enabled by rails integration so should only auto instrument
        # if detected that it is being used without rails
        def auto_instrument?
          !Contrib::Rails::Utils.railtie_supported?
        end

        def new_configuration
          Configuration::Settings.new
        end

        def patcher
          ActiveSupport::Patcher
        end
      end
    end
  end
end
