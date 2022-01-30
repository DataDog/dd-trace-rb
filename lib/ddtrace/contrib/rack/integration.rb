# typed: false
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/rack/configuration/settings'
require 'ddtrace/contrib/rack/patcher'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Tracing
    module Contrib
      module Rack
        # Description of Rack integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('1.1.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :rack, auto_patch: false

          def self.version
            Gem.loaded_specs['rack'] && Gem.loaded_specs['rack'].version
          end

          def self.loaded?
            !defined?(::Rack).nil?
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
