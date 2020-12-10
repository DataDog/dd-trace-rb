require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/action_pack/configuration/settings'
require 'ddtrace/contrib/action_pack/patcher'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module ActionPack
      # Describes the ActionPack integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('3.0')

        register_as :action_pack, auto_patch: false

        def self.version
          Gem.loaded_specs['actionpack'] && Gem.loaded_specs['actionpack'].version
        end

        def self.loaded?
          !defined?(::ActionPack).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        # enabled by rails integration so should only auto instrument
        # if detected that it is being used without rails
        def auto_instrument?
          !Datadog::Contrib::Rails::Utils.railtie_supported?
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          ActionPack::Patcher
        end
      end
    end
  end
end
