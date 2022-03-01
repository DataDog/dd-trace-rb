# typed: false

require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/rack/configuration/settings'
require 'datadog/tracing/contrib/rack/patcher'
require 'datadog/tracing/contrib/rails/utils'

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
