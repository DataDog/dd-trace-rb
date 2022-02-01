# typed: false
require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/action_cable/configuration/settings'
require 'datadog/tracing/contrib/action_cable/patcher'
require 'datadog/tracing/contrib/rails/utils'

module Datadog
  module Tracing
    module Contrib
      module ActionCable
        # Description of ActionCable integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('5.0.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :action_cable, auto_patch: false

          def self.version
            Gem.loaded_specs['actioncable'] && Gem.loaded_specs['actioncable'].version
          end

          def self.loaded?
            !defined?(::ActionCable).nil?
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
            Patcher
          end
        end
      end
    end
  end
end
