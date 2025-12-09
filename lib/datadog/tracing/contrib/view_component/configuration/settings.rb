# frozen_string_literal: true

require_relative '../../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module ViewComponent
        module Configuration
          # Custom settings for the ViewComponent integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end

            # @!visibility private
            option :analytics_enabled do |o|
              o.type :bool
              o.env Ext::ENV_ANALYTICS_ENABLED
              o.default false
            end

            # TODO: Rename to components_base_path when revisiting the ActionView refactor
            # The ViewComponent and ActionView configurations should mirror each other, since they're generally
            # run together. We may also need to revisit that the format is correct.
            # see: https://github.com/DataDog/dd-trace-rb/pull/4977#discussion_r2440187824
            option :service_name
            option :component_base_path do |o|
              o.type :string
              o.default 'components/'
            end

            option :use_deprecated_instrumentation_name do |o|
              o.type :bool
              o.default false
            end
          end
        end
      end
    end
  end
end
