# frozen_string_literal: true

require_relative 'event'
require_relative 'metric'

module Datadog
  module Core
    module Telemetry
      # MetricsCollection is a thread-safe collection of metrics per namespace
      class MetricsCollection
        attr_reader :namespace

        def initialize(namespace, aggregation_interval:)
          @namespace = namespace
          @interval = aggregation_interval

          @mutex = Mutex.new

          @metrics = {}
          @distributions = {}
        end

        def inc(metric_name, value, tags: {}, common: true)
          metric = Metric::Count.new(metric_name, tags: tags, common: common)

          @mutex.synchronize do
            if @metrics.key?(metric.id)
              metric = @metrics[metric.id]
            else
              @metrics[metric.id] = metric
            end

            metric.inc(value)
          end
          nil
        end

        def dec(metric_name, value, tags: {}, common: true)
          metric = Metric::Count.new(metric_name, tags: tags, common: common)

          @mutex.synchronize do
            if @metrics.key?(metric.id)
              metric = @metrics[metric.id]
            else
              @metrics[metric.id] = metric
            end

            metric.dec(value)
          end
          nil
        end

        def gauge(metric_name, value, tags: {}, common: true)
          metric = Metric::Gauge.new(metric_name, tags: tags, common: common, interval: @interval)

          @mutex.synchronize do
            if @metrics.key?(metric.id)
              metric = @metrics[metric.id]
            else
              @metrics[metric.id] = metric
            end

            metric.track(value)
          end
          nil
        end

        def rate(metric_name, value, tags: {}, common: true)
          metric = Metric::Rate.new(metric_name, tags: tags, common: common, interval: @interval)

          @mutex.synchronize do
            if @metrics.key?(metric.id)
              metric = @metrics[metric.id]
            else
              @metrics[metric.id] = metric
            end

            metric.track(value)
          end
          nil
        end

        def distribution(metric_name, value, tags: {}, common: true)
          metric = Metric::Distribution.new(metric_name, tags: tags, common: common)

          @mutex.synchronize do
            if @distributions.key?(metric.id)
              metric = @distributions[metric.id]
            else
              @distributions[metric.id] = metric
            end

            metric.track(value)
          end
          nil
        end

        def flush!(queue)
          @mutex.synchronize do
            queue.enqueue(Event::GenerateMetrics.new(@namespace, @metrics.values)) if @metrics.any?
            queue.enqueue(Event::Distributions.new(@namespace, @distributions.values)) if @distributions.any?

            @metrics = {}
            @distributions = {}
          end
          nil
        end
      end
    end
  end
end
