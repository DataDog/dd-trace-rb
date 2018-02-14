module Datadog
  module Contrib
    module Rails
      # Patcher
      module Patcher
        include Base
        register_as :rails, auto_patch: true

        option :service_name
        option :controller_service
        option :cache_service
        option :database_service
        option :distributed_tracing, default: false
        option :template_base_path, default: 'views/'
        option :exception_controller, default: nil
        option :controller_callback_tracing, default: false do |value|
          controller_callback_tracing_supported? ? value : false
        end
        option :tracer, default: Datadog.tracer

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

          def active_record_instantiation_tracing_supported?
            Gem.loaded_specs['activerecord'] \
              && Gem.loaded_specs['activerecord'].version >= Gem::Version.new('4.2')
          end

          def controller_callback_tracing_supported?
            defined?(::Rails) \
              && Gem::Version.new(::Rails.version) >= Gem::Version.new('5.0') \
              && Gem::Version.new(::Rails.version) < Gem::Version.new('5.2')
          end
        end
      end
    end
  end
end

require 'ddtrace/contrib/rails/railtie' if Datadog.registry[:rails].compatible?
