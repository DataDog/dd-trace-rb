# typed: true

require_relative 'ext'

require_relative '../metrics/client'
require_relative '../environment/class_count'
require_relative '../environment/gc'
require_relative '../environment/thread_count'
require_relative '../environment/vm_cache'

module Datadog
  module Core
    module Runtime
      # For generating runtime metrics
      class Metrics < Core::Metrics::Client
        def initialize(**options)
          super

          # Initialize service list
          @services = Set.new(options.fetch(:services, []))
          @service_tags = nil
          compile_service_tags!
        end

        # Associate service with runtime metrics
        def register_service(service)
          return unless enabled? && service

          service = service.to_s

          unless @services.include?(service)
            # Add service to list and update services tag
            services << service

            # Recompile the service tags
            compile_service_tags!
          end
        end

        # Flush all runtime metrics to Statsd client
        def flush
          return unless enabled?

          try_flush do
            if Core::Environment::ClassCount.available?
              gauge(Core::Runtime::Ext::Metrics::METRIC_CLASS_COUNT, Core::Environment::ClassCount.value)
            end
          end

          try_flush do
            if Core::Environment::ThreadCount.available?
              gauge(Core::Runtime::Ext::Metrics::METRIC_THREAD_COUNT, Core::Environment::ThreadCount.value)
            end
          end

          try_flush { gc_metrics.each { |metric, value| gauge(metric, value) } if Core::Environment::GC.available? }

          try_flush do
            if Core::Environment::VMCache.available?
              gauge(
                Core::Runtime::Ext::Metrics::METRIC_GLOBAL_CONSTANT_STATE,
                Core::Environment::VMCache.global_constant_state
              )

              # global_method_state is not available since Ruby >= 3.0,
              # as method caching was moved to a per-class basis.
              global_method_state = Core::Environment::VMCache.global_method_state
              gauge(Core::Runtime::Ext::Metrics::METRIC_GLOBAL_METHOD_STATE, global_method_state) if global_method_state
            end
          end
        end

        def gc_metrics
          Core::Environment::GC.stat.flat_map do |k, v|
            nested_gc_metric(Core::Runtime::Ext::Metrics::METRIC_GC_PREFIX, k, v)
          end.to_h
        end

        def try_flush
          yield
        rescue StandardError => e
          Datadog.logger.error("Error while sending runtime metric. Cause: #{e.class.name} #{e.message}")
        end

        def default_metric_options
          # Return dupes, so that the constant isn't modified,
          # and defaults are unfrozen for mutation in Statsd.
          super.tap do |options|
            options[:tags] = options[:tags].dup

            # Add services dynamically because they might change during runtime.
            options[:tags].concat(service_tags) unless service_tags.nil?
          end
        end

        private

        attr_reader \
          :service_tags,
          :services

        def compile_service_tags!
          @service_tags = services.to_a.collect do |service|
            "#{Core::Runtime::Ext::Metrics::TAG_SERVICE}:#{service}".freeze
          end
        end

        def nested_gc_metric(prefix, k, v)
          path = "#{prefix}.#{k}"

          if v.is_a?(Hash)
            v.flat_map do |key, value|
              nested_gc_metric(path, key, value)
            end
          else
            [[to_metric_name(path), v]]
          end
        end

        def to_metric_name(str)
          str.downcase.gsub(/[-\s]/, '_')
        end
      end
    end
  end
end
