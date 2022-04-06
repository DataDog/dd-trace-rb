# typed: ignore

require 'datadog/appsec/contrib/integration'

require 'datadog/appsec/contrib/rack/configuration/settings'
require 'datadog/appsec/contrib/rack/patcher'
require 'datadog/appsec/contrib/rack/request_middleware'
require 'datadog/appsec/contrib/rack/request_body_middleware'

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Description of Rack integration
        class Integration
          include Datadog::AppSec::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('1.1.0')

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

          def self.auto_instrument?
            false
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
end
