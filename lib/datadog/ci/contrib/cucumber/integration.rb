require 'ddtrace/contrib/integration'

require 'datadog/ci/contrib/cucumber/configuration/settings'
require 'datadog/ci/contrib/cucumber/patcher'

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Description of Cucumber integration
        class Integration
          include Datadog::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('3.0.0')

          register_as :cucumber, auto_patch: true

          def self.version
            Gem.loaded_specs['cucumber'] \
              && Gem.loaded_specs['cucumber'].version
          end

          def self.loaded?
            !defined?(::Cucumber).nil? && !defined?(::Cucumber::Runtime).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          # test environments should not auto instrument test libraries
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
