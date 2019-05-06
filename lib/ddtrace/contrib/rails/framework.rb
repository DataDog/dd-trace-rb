require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/active_record/integration'
require 'ddtrace/contrib/active_support/integration'
require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/rack/middlewares'

require 'ddtrace/contrib/rails/ext'
require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/action_controller'
require 'ddtrace/contrib/rails/action_view'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    # Instrument Rails.
    module Rails
      # Rails framework code, used to essentially:
      # - handle configuration entries which are specific to Datadog tracing
      # - instrument parts of the framework when needed
      module Framework
        # configure Datadog settings
        def self.setup
          config = config_with_defaults

          activate_rack!(config)
          activate_active_support!(config)
          activate_active_record!(config)

          # By default, default service would be guessed from the script
          # being executed, but here we know better, get it from Rails config.
          config[:tracer].default_service = config[:service_name]
        end

        def self.config_with_defaults
          # We set defaults here instead of in the patcher because we need to wait
          # for the Rails application to be fully initialized.
          Datadog.configuration[:rails].tap do |config|
            config[:service_name] ||= Utils.app_name
            config[:database_service] ||= "#{config[:service_name]}-#{Contrib::ActiveRecord::Utils.adapter_name}"
            config[:controller_service] ||= config[:service_name]
            config[:cache_service] ||= "#{config[:service_name]}-cache"
          end
        end

        def self.activate_rack!(config)
          Datadog.configuration.use(
            :rack,
            tracer: config[:tracer],
            application: ::Rails.application,
            service_name: config[:service_name],
            middleware_names: config[:middleware_names],
            distributed_tracing: config[:distributed_tracing]
          )
        end

        def self.activate_active_support!(config)
          return unless defined?(::ActiveSupport)

          Datadog.configuration.use(
            :active_support,
            service_name: config[:cache_service],
            tracer: config[:tracer]
          )

          reload_cache_store
        end

        def self.reload_cache_store
          return unless Datadog.registry[:redis] &&
                        Datadog.registry[:redis].patcher.patched?

          return unless defined?(::ActiveSupport::Cache::RedisStore) &&
                        ::Rails.respond_to?(:cache) &&
                        ::Rails.cache.is_a?(::ActiveSupport::Cache::RedisStore)

          Tracer.log.debug('Reloading redis cache store')

          # backward compatibility: Rails 3.x doesn't have `cache=` method
          cache_store = ::Rails.configuration.cache_store
          cache_instance = ::ActiveSupport::Cache.lookup_store(cache_store)
          if ::Rails::VERSION::MAJOR.to_i == 3
            silence_warnings { Object.const_set 'RAILS_CACHE', cache_instance }
          elsif ::Rails::VERSION::MAJOR.to_i > 3
            ::Rails.cache = cache_instance
          end
        end

        def self.activate_active_record!(config)
          return unless defined?(::ActiveRecord)

          Datadog.configuration.use(
            :active_record,
            service_name: config[:database_service],
            tracer: config[:tracer]
          )
        end
      end
    end
  end
end
