# frozen_string_literal: true

require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'
require_relative '../rails/utils'

module Datadog
  module Tracing
    module Contrib
      module ActiveStorage
        # Description of ActiveStorage integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('5.0.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :active_storage, auto_patch: false

          def self.version
            Gem.loaded_specs['activestorage'] && Gem.loaded_specs['activestorage'].version
          end

          def self.loaded?
            !defined?(::ActiveStorage).nil?
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
