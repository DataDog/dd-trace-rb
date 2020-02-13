require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/action_pack/configuration/settings'
require 'ddtrace/contrib/action_pack/patcher'

module Datadog
  module Contrib
    module ActionPack
      # Describes the ActionPack integration
      class Integration
        include Contrib::Integration

        register_as :action_pack, auto_patch: false

        def self.version
          Gem.loaded_specs['actionpack'] && Gem.loaded_specs['actionpack'].version
        end

        def self.loaded?
          defined?(::ActionPack)
        end

        def self.compatible?
          super && version >= Gem::Version.new('3.0')
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
