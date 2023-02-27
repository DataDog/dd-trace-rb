require_relative '../../configuration/settings'

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
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end

            option :analytics_enabled do |o|
              o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, nil) }
              o.lazy
              o.on_set do |value|
                # Update ActionPack analytics too
                Datadog.configuration.tracing[:action_pack][:analytics_enabled] = value
              end
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
              o.lazy
              o.on_set do |value|
                # Update ActionPack analytics too
                Datadog.configuration.tracing[:action_pack][:analytics_sample_rate] = value
              end
            end

            option :distributed_tracing, default: true

            option :request_queuing, default: false

            option :exception_controller do |o|
              o.on_set do |value|
                # Update ActionPack exception controller too
                Datadog.configuration.tracing[:action_pack][:exception_controller] = value
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
