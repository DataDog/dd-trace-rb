require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Rails
      module Configuration
        # Custom settings for the Rails integration
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
            o.default { env_to_bool([Ext::ENV_ANALYTICS_ENABLED, Ext::ENV_ANALYTICS_ENABLED_OLD], nil) }
            o.lazy
            o.on_set do |value|
              # Update ActionPack analytics too
              Datadog.configuration[:action_pack][:analytics_enabled] = value
            end
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float([Ext::ENV_ANALYTICS_SAMPLE_RATE, Ext::ENV_ANALYTICS_SAMPLE_RATE_OLD], 1.0) }
            o.lazy
            o.on_set do |value|
              # Update ActionPack analytics too
              Datadog.configuration[:action_pack][:analytics_sample_rate] = value
            end
          end

          option :cache_service do |o|
            o.on_set do |value|
              # Update ActiveSupport service name too
              Datadog.configuration[:active_support][:cache_service] = value
            end
          end

          option :controller_service do |o|
            o.on_set do |value|
              # Update ActionPack service name too
              Datadog.configuration[:action_pack][:controller_service] = value
            end
          end

          option :database_service do |o|
            o.depends_on :service_name
            o.on_set do |value|
              # Update ActiveRecord service name too
              Datadog.configuration[:active_record][:service_name] = value
            end
          end

          option :distributed_tracing, default: true
          option :exception_controller do |o|
            o.on_set do |value|
              # Update ActionPack exception controller too
              Datadog.configuration[:action_pack][:exception_controller] = value
            end
          end

          option :middleware, default: true
          option :middleware_names, default: false
          option :template_base_path do |o|
            o.default 'views/'
            o.on_set do |value|
              # Update ActionView template base path too
              Datadog.configuration[:action_view][:template_base_path] = value
            end
          end

          option :log_injection do |o|
            o.default { env_to_bool(Ext::ENV_LOGS_INJECTION_ENABLED, false) }
            o.lazy
          end
        end
      end
    end
  end
end
