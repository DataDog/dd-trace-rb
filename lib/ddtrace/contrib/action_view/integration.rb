require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/action_view/configuration/settings'
require 'ddtrace/contrib/action_view/patcher'

module Datadog
  module Contrib
    module ActionView
      # Describes the ActionView integration
      class Integration
        include Contrib::Integration

        register_as :action_view, auto_patch: false

        def self.version
          Gem.loaded_specs['actionview'] && Gem.loaded_specs['actionview'].version
        end

        def self.present?
          super && defined?(::ActionView)
        end

        def self.compatible?
          super && version >= Gem::Version.new('3.0')
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          ActionView::Patcher
        end
      end
    end
  end
end
