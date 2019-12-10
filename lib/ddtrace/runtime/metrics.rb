require 'ddtrace/ext/runtime'

require 'ddtrace/metrics'
require 'ddtrace/runtime/class_count'
require 'ddtrace/runtime/gc'
require 'ddtrace/runtime/identity'
require 'ddtrace/runtime/thread_count'

module Datadog
  module Runtime
    # For generating runtime metrics
    class Metrics < Datadog::Metrics
      def initialize(options = {})
        super

        # Initialize service list
        @services = Set.new
        @service_tags = nil
      end

      def associate_with_span(span)
        return if span.nil?

        # Register service as associated with metrics
        register_service(span.service) unless span.service.nil?

        # Tag span with language and runtime ID for association with metrics
        span.set_tag(Ext::Runtime::TAG_LANG, Runtime::Identity.lang)
      end

      # Associate service with runtime metrics
      def register_service(service)
        return if service.nil?

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

        try_flush { gauge(Ext::Runtime::Metrics::METRIC_CLASS_COUNT, ClassCount.value) if ClassCount.available? }
        try_flush { gauge(Ext::Runtime::Metrics::METRIC_THREAD_COUNT, ThreadCount.value) if ThreadCount.available? }
        try_flush { gc_metrics.each { |metric, value| gauge(metric, value) } if GC.available? }
      end

      def gc_metrics
        Hash[
          GC.stat.map do |k, v|
            ["#{Ext::Runtime::Metrics::METRIC_GC_PREFIX}.#{k}", v]
          end
        ]
      end

      def try_flush
        yield
      rescue StandardError => e
        Datadog::Logger.log.error("Error while sending runtime metric. Cause: #{e.message}")
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
          "#{Ext::Runtime::Metrics::TAG_SERVICE}:#{service}".freeze
        end
      end
    end
  end
end
