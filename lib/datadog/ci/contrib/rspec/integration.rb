require 'ddtrace/contrib/integration'

require 'datadog/ci/contrib/rspec/configuration/settings'
require 'datadog/ci/contrib/rspec/patcher'

module Datadog
  module CI
    module Contrib
      module RSpec
        # Description of RSpec integration
        class Integration
          include Datadog::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('3.0.0')

          register_as :rspec, auto_patch: true

          def self.version
            Gem.loaded_specs['rspec'] \
              && Gem.loaded_specs['rspec'].version
          end

          def self.loaded?
            !defined?(::RSpec).nil? && !defined?(::RSpec::Core).nil? && \
              !defined?(::RSpec::Core::Example).nil?
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
