require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module Roda
        # Description of Roda integration
        class Integration
          include Contrib::Integration

          register_as :roda

          def self.version
            Gem.loaded_specs['roda'] && Gem.loaded_specs['roda'].version
          end

          def self.loaded?
            !defined?(::Roda).nil?
          end

          def self.compatible?
            super && version >= Gem::Version.new('2.0.0')
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
