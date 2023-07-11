require_relative '../../configuration/settings'

require_relative '../../../../core'

module Datadog
  module Tracing
    module Contrib
      module Rails
        module Configuration
          # Custom settings for the Rails integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            def initialize(options = {})
              super(options)

              # NOTE: Eager load these
              #       Rails integration is responsible for orchestrating other integrations.
              #       When using environment variables, settings will not be automatically
              #       filled because nothing explicitly calls them. They must though, so
              #       integrations like ActionPack can receive the value as it should.
              #       Trigger these manually to force an eager load and propagate them.
              analytics_enabled
              analytics_sample_rate
            end

            option :enabled do |o|
              o.env_var Ext::ENV_ENABLED
              o.default true
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :analytics_enabled do |o|
              o.env_var Ext::ENV_ANALYTICS_ENABLED
              o.setter do |value|
                val_to_bool(value) unless value.nil?
              end

              o.on_set do |value|
                # Update ActionPack analytics too
                Datadog.configuration.tracing[:action_pack][:analytics_enabled] = value unless value.nil?
              end
            end

            option :analytics_sample_rate do |o|
              o.env_var Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
              o.setter do |value|
                val_to_float(value)
              end

              o.on_set do |value|
                # Update ActionPack analytics too
                Datadog.configuration.tracing[:action_pack][:analytics_sample_rate] = value
              end
            end

            option :distributed_tracing, default: true

            option :request_queuing, default: false

            # DEV-2.0: Breaking changes for removal.
            option :exception_controller do |o|
              o.on_set do |value|
                if value
                  Datadog::Core.log_deprecation do
                    'The error controller is now automatically detected. '\
                    "Option `#{o.instance_variable_get(:@name)}` is no longer required and will be removed."
                  end
                end
              end
            end

            option :middleware, default: true
            option :middleware_names, default: false
            option :template_base_path do |o|
              o.default 'views/'
              o.on_set do |value|
                # Update ActionView template base path too
                Datadog.configuration.tracing[:action_view][:template_base_path] = value
              end
            end
          end
        end
      end
    end
  end
end
