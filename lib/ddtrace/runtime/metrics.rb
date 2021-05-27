require 'ddtrace/ext/integration'
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
        @services = Set.new(options.fetch(:services, []))
        @service_tags = nil
        compile_service_tags!
      end

      def associate_with_span(span)
        return if !enabled? || span.nil?

        # Register service as associated with metrics
        register_service(span.service) unless span.service.nil?

        # Tag span with language and runtime ID for association with metrics.
        # We only tag spans that performed internal application work.
        unless span.get_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE)
          span.set_tag(Ext::Runtime::TAG_LANG, Runtime::Identity.lang)
        end
      end

      # Associate service with runtime metrics
      def register_service(service)
        return if !enabled? || service.nil?

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
        GC.stat.flat_map do |k, v|
          nested_gc_metric(Ext::Runtime::Metrics::METRIC_GC_PREFIX, k, v)
        end.to_h
      end

      def try_flush
        yield
      rescue StandardError => e
        Datadog.logger.error("Error while sending runtime metric. Cause: #{e.message}")
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
