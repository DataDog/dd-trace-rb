require 'ddtrace/ext/meta'
require 'ddtrace/ext/metrics'

require 'ddtrace/utils/time'

module Datadog
  # Behavior for sending statistics to Statsd
  module Metrics
    DEFAULT_OPTIONS = {
      tags: DEFAULT_TAGS = [
        "#{Ext::Metrics::TAG_LANG}:#{Ext::Meta::LANG}".freeze,
        "#{Ext::Metrics::TAG_LANG_INTERPRETER}:#{Ext::Meta::LANG_INTERPRETER}".freeze,
        "#{Ext::Metrics::TAG_LANG_VERSION}:#{Ext::Meta::LANG_VERSION}".freeze,
        "#{Ext::Metrics::TAG_TRACER_VERSION}:#{Ext::Meta::TRACER_VERSION}".freeze
      ].freeze
    }.freeze

    attr_accessor :statsd

    protected

    def distribution(stat, value, options = nil)
      return if statsd.nil?
      statsd.distribution(stat, value, metric_options(options))
    end

    def increment(stat, options = nil)
      return if statsd.nil?
      statsd.increment(stat, metric_options(options))
    end

    def time(stat, options = nil, &block)
      return yield if statsd.nil?

      # Calculate time, send it as a distribution.
      start = Utils::Time.get_time
      return yield
    ensure
      unless statsd.nil?
        finished = Utils::Time.get_time
        statsd.distribution(stat, ((finished - start) * 1000), metric_options(options))
      end
    end

    def metric_options(options = nil)
      return default_metric_options if options.nil?

      default_metric_options.merge(options) do |key, old_value, new_value|
        case key
        when :tags
          old_value.dup.concat(new_value)
        else
          new_value
        end
      end
    end

    def default_metric_options
      DEFAULT_OPTIONS
    end
  end
end
