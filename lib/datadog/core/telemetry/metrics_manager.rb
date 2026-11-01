# frozen_string_literal: true

require_relative "metrics_collection"

module Datadog
  module Core
    module Telemetry
      # MetricsManager aggregates and flushes metrics and distributions
      #
      # @api private
      class MetricsManager
        attr_reader :enabled
        attr_reader :collections
        # The registered metric sources, in registration order.
        # @return [Array<#report_metrics, #clear_metrics>]
        attr_reader :sources

        def initialize(aggregation_interval:, enabled:)
          @interval = aggregation_interval
          @enabled = enabled
          @mutex = Mutex.new

          @collections = {}
          @sources = []
        end

        # Registers a metric source: an object that aggregates metrics
        # locally and records them into this manager at each flush. A
        # source responds to #report_metrics(metrics_manager), which records
        # its aggregated metrics through #inc and the other recording
        # methods, and to #clear_metrics, which discards them. Sources
        # contain their own reporting failures.
        #
        # @param source [#report_metrics, #clear_metrics] the metric source
        # @return [void]
        def register_source(source)
          mutex.synchronize do
            sources << source unless sources.include?(source)
          end
          nil
        end

        # Unregisters a metric source, then asks it to report the metrics it
        # aggregated before unregistration so that the next flush sends them.
        #
        # @param source [#report_metrics, #clear_metrics] the metric source
        # @return [void]
        def unregister_source(source)
          removed = mutex.synchronize { sources.delete(source) }
          source.report_metrics(self) if removed
          nil
        end

        def inc(namespace, metric_name, value, tags: {}, common: true)
          return unless @enabled

          # collection is thread-safe internally
          collection = fetch_or_create_collection(namespace)
          collection.inc(metric_name, value, tags: tags, common: common)
        end

        def dec(namespace, metric_name, value, tags: {}, common: true)
          return unless @enabled

          # collection is thread-safe internally
          collection = fetch_or_create_collection(namespace)
          collection.dec(metric_name, value, tags: tags, common: common)
        end

        def gauge(namespace, metric_name, value, tags: {}, common: true)
          return unless @enabled

          # collection is thread-safe internally
          collection = fetch_or_create_collection(namespace)
          collection.gauge(metric_name, value, tags: tags, common: common)
        end

        def rate(namespace, metric_name, value, tags: {}, common: true)
          return unless @enabled

          # collection is thread-safe internally
          collection = fetch_or_create_collection(namespace)
          collection.rate(metric_name, value, tags: tags, common: common)
        end

        def distribution(namespace, metric_name, value, tags: {}, common: true)
          return unless @enabled

          # collection is thread-safe internally
          collection = fetch_or_create_collection(namespace)
          collection.distribution(metric_name, value, tags: tags, common: common)
        end

        # Collects the metrics aggregated since the previous flush: asks
        # every registered source to report its metrics, then drains the
        # namespace collections.
        #
        # @return [Array<Event::GenerateMetrics, Event::Distributions>] the metric events, empty when disabled
        def flush!
          return [] unless @enabled

          registered_sources = mutex.synchronize { sources.dup }
          registered_sources.each { |source| source.report_metrics(self) }

          collections = mutex.synchronize { @collections.values }
          collections.reduce([]) { |events, collection| events + collection.flush! }
        end

        def disable!
          @enabled = false
        end

        # Discards the aggregated metrics of the collections and of every
        # registered source. Called in a forked child, whose parent sends
        # the metrics aggregated before the fork.
        #
        # @return [void]
        def clear
          registered_sources = mutex.synchronize do
            @collections = {}
            sources.dup
          end
          registered_sources.each(&:clear_metrics)
          nil
        end

        private

        attr_reader :mutex

        def fetch_or_create_collection(namespace)
          mutex.synchronize do
            @collections[namespace] ||= MetricsCollection.new(namespace, aggregation_interval: @interval)
          end
        end
      end
    end
  end
end
