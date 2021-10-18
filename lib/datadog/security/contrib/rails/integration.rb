require 'datadog/security/contrib/integration'

require 'datadog/security/contrib/rails/configuration/settings'
require 'datadog/security/contrib/rails/patcher'
require 'datadog/security/contrib/rails/request_middleware'

module Datadog
  module Security
    module Contrib
      module Rails
        # Description of Rails integration
        class Integration
          include Datadog::Security::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('3.2.0')

          register_as :rails, auto_patch: false

          def self.version
            Gem.loaded_specs['rails'] && Gem.loaded_specs['rails'].version
          end

          def self.loaded?
            !defined?(::Rails).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def auto_instrument?
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


