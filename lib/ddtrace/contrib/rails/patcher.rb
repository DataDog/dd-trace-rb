module Datadog
  module Contrib
    module Rails
      # Patcher
      module Patcher
        include Base
        register_as :rails, auto_patch: true

        option :enabled, default: true
        option :auto_instrument, default: false
        option :auto_instrument_redis, default: false
        option :auto_instrument_grape, default: false
        option :default_service, default: 'rails-app'
        option :default_controller_service, default: 'rails-controller'
        option :default_cache_service, default: 'rails-cache'
        option :default_grape_service, default: 'grape'
        option :default_database_service
        option :distributed_tracing_enabled, default: false
        option :priority_sampling, default: false
        option :template_base_path, default: 'views/'
        option :tracer, default: Datadog.tracer
        option :debug, default: false
        option :trace_agent_hostname, default: Datadog::Writer::HOSTNAME
        option :trace_agent_port, default: Datadog::Writer::PORT
        option :env, default: nil
        option :tags, default: {}

        @patched = false

        class << self
          def patch
            return @patched if patched? || !compatible?
            require_relative 'framework'
            @patched = true
          rescue => e
            Datadog::Tracer.log.error("Unable to apply Rails integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          def compatible?
            return if ENV['DISABLE_DATADOG_RAILS']

            defined?(::Rails::VERSION) && ::Rails::VERSION::MAJOR.to_i >= 3
          end
        end
      end
    end
  end
end

require 'ddtrace/contrib/rails/railtie' if Datadog.registry[:rails].compatible?
