require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module Presto
        # Description of Presto integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('0.5.14')

          def self.gems
            ['presto']
          end

          def self.version
            Gem.loaded_specs['presto-client'] && Gem.loaded_specs['presto-client'].version
          end

          def self.loaded?
            !defined?(::Presto::Client::Client).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :presto
        end
      end
    end
  end
end
