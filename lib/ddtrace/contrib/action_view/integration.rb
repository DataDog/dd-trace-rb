# typed: false
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/action_view/configuration/settings'
require 'ddtrace/contrib/action_view/patcher'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module ActionView
      # Describes the ActionView integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('3.2')

        # @public_api Changing the integration name or integration options can cause breaking changes
        register_as :action_view, auto_patch: false

        def self.version
          # ActionView is its own gem in Rails 4.1+
          if Gem.loaded_specs['actionview']
            Gem.loaded_specs['actionview'].version
          # ActionView is embedded in ActionPack in versions < 4.1
          elsif Gem.loaded_specs['actionpack']
            action_pack_version = Gem.loaded_specs['actionpack'].version
            action_pack_version unless action_pack_version >= Gem::Version.new('4.1')
          end
        end

        def self.loaded?
          !defined?(::ActionView).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        # enabled by rails integration so should only auto instrument
        # if detected that it is being used without rails
        def auto_instrument?
          !Datadog::Contrib::Rails::Utils.railtie_supported?
        end

        def new_configuration
          Configuration::Settings.new
        end

        def patcher
          ActionView::Patcher
        end
      end
    end
  end
end
