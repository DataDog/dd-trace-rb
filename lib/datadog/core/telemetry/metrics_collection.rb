# frozen_string_literal: true

require_relative 'metric'

module Datadog
  module Core
    module Telemetry
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
          metric_id = Metric.metric_id(Metric::Count::TYPE, metric_name, tags)

          @mutex.synchronize do
            metric = @metrics.key?[metric_id]
            if metric.nil?
              metric = Metric::Count.new(metric_name, tags: tags, common: common)
              @metrics[metric_id] = metric
            end

            metric.inc(value)
          end
        end

        def dec(metric_name, value, tags: {}, common: true)
          metric_id = Metric.metric_id(Metric::Count::TYPE, metric_name, tags)

          @mutex.synchronize do
            metric = @metrics.key?[metric_id]
            if metric.nil?
              metric = Metric::Count.new(metric_name, tags: tags, common: common)
              @metrics[metric_id] = metric
            end

            metric.dec(value)
          end
        end

        def gauge(metric_name, value, tags: {}, common: true)
          metric_id = Metric.metric_id(Metric::Gauge::TYPE, metric_name, tags)

          @mutex.synchronize do
            metric = @metrics.key?[metric_id]
            if metric.nil?
              metric = Metric::Gauge.new(metric_name, tags: tags, common: common, interval: @interval)
              @metrics[metric_id] = metric
            end

            metric.track(value)
          end
        end

        def rate(metric_name, value, tags: {}, common: true)
          metric_id = Metric.metric_id(Metric::Rate::TYPE, metric_name, tags) # this will fail, it expects array of tags

          @mutex.synchronize do
            metric = @metrics.key?[metric_id]
            if metric.nil?
              metric = Metric::Rate.new(metric_name, tags: tags, common: common, interval: @interval)
              @metrics[metric_id] = metric
            end

            metric.track(value)
          end
        end

        def distribution(metric_name, value, tags: {}, common: true)
          metric_id = Metric.metric_id(Metric::Distribution::TYPE, metric_name, tags)

          @mutex.synchronize do
            metric = @distributions.key?[metric_id]
            if metric.nil?
              metric = Metric::Distribution.new(metric_name, tags: tags, common: common)
              @distributions[metric_id] = metric
            end

            metric.track(value)
          end
        end

        def flush!
          events = []

          @mutex.synchronize do
            events << Event::GenerateMetrics.new(@namespace, @metrics.values) if @metrics.any?

            events << Event::Distributions.new(@namespace, @distributions.values) if @distributions.any?

            @metrics = {}
            @distributions = {}
          end

          events
        end
      end
    end
  end
end
