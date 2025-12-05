# frozen_string_literal: true

require_relative 'configuration/settings'
require_relative 'patcher'
require_relative '../integration'
require_relative '../rails/ext'
require_relative '../../../core/contrib/rails/utils'

module Datadog
  module Tracing
    module Contrib
      module ViewComponent
        # Describes the ViewComponent integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = "2.34.0"

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :view_component, auto_patch: false
          def self.gem_name
            'view_component'
          end

          def self.version
            Gem.loaded_specs['view_component']&.version
          end

          def self.loaded?
            !defined?(::ViewComponent).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            ViewComponent::Patcher
          end
        end
      end
    end
  end
end
