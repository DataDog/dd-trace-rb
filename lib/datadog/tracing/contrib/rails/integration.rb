require_relative '../integration'

require_relative 'ext'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module Rails
        # Description of Rails integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('3.2')

          def self.gems
            ['railties']
          end

          def self.version
            Gem.loaded_specs['railties'] && Gem.loaded_specs['railties'].version
          end

          def self.loaded?
            !defined?(::Rails).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def self.patchable?
            super && !ENV.key?(Ext::ENV_DISABLE)
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :rails, auto_patch: false
        end
      end
    end
  end
end
