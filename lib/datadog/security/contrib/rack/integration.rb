# typed: ignore

require 'datadog/security/contrib/integration'

require 'datadog/security/contrib/rack/configuration/settings'
require 'datadog/security/contrib/rack/patcher'
require 'datadog/security/contrib/rack/request_middleware'

module Datadog
  module Security
    module Contrib
      module Rack
        # Description of Rack integration
        class Integration
          include Datadog::Security::Contrib::Integration

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
