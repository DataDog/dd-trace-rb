require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Rails
      module Configuration
        # Custom settings for the Rails integration
        class Settings < Contrib::Configuration::Settings
          COMPONENTS = [
            :active_record,
            :action_view,
            :action_pack,
            :active_support,
            :rack
          ].freeze

          integration :rack, defer: true do |rack|
            rack.tracer = tracer
            rack.application = ::Rails.application
            rack.service_name = service_name
            rack.middleware_names = middleware_names
            rack.distributed_tracing = distributed_tracing
          end

          integration :active_support, defer: true do |active_support|
            active_support.cache_service = cache_service
            active_support.tracer = tracer
          end

          integration :action_pack, defer: true do |action_pack|
            action_pack.service_name = service_name
            action_pack.tracer = tracer
          end

          integration :action_view, defer: true do |action_view|
            action_view.service_name = service_name
            action_view.tracer = tracer
          end

          integration :active_record, defer: true do |active_record|
            active_record.service_name = database_service
            active_record.tracer = tracer
          end

          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, nil) },
                  lazy: true do |value|
            value.tap do
              # Update ActionPack analytics too
              Datadog.configuration[:action_pack][:analytics_enabled] = value
            end
          end

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true do |value|
            value.tap do
              # Update ActionPack analytics too
              Datadog.configuration[:action_pack][:analytics_sample_rate] = value
            end
          end

          option :cache_service do |value|
            value.tap do
              # Update ActiveSupport service name too
              Datadog.configuration[:active_support][:cache_service] = value
            end
          end
          option :controller_service do |value|
            value.tap do
              # Update ActionPack service name too
              Datadog.configuration[:action_pack][:controller_service] = value
            end
          end
          option :database_service, depends_on: [:service_name] do |value|
            value.tap do
              # Update ActiveRecord service name too
              Datadog.configuration[:active_record][:service_name] = value
            end
          end
          option :distributed_tracing, default: true
          option :exception_controller, default: nil do |value|
            value.tap do
              # Update ActionPack exception controller too
              Datadog.configuration[:action_pack][:exception_controller] = value
            end
          end
          option :middleware, default: true
          option :middleware_names, default: false
          option :template_base_path, default: 'views/' do |value|
            # Update ActionView template base path too
            value.tap { Datadog.configuration[:action_view][:template_base_path] = value }
          end

          option :tracer, default: Datadog.tracer do |value|
            value.tap do
              Datadog.configuration[:rack][:tracer] = value
              COMPONENTS.each { |name| Datadog.configuration[name][:tracer] = value }
            end
          end
        end
      end
    end
  end
end
