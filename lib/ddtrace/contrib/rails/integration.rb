require 'ddtrace/contrib/integration'

require 'ddtrace/contrib/rails/ext'
require 'ddtrace/contrib/rails/configuration/settings'
require 'ddtrace/contrib/rails/patcher'

module Datadog
  module Contrib
    module Rails
      # Description of Rails integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('3.0')

        register_as :rails, auto_patch: false

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
