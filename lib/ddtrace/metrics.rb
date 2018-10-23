require 'ddtrace/ext/meta'
require 'ddtrace/ext/statsd'

module Datadog
  # Behavior for sending statistics to Statsd
  module Metrics
    DEFAULT_OPTIONS = {
      tags: DEFAULT_TAGS = [
        "#{Ext::Statsd::TAG_LANG}:#{Ext::Meta::LANG}".freeze,
        "#{Ext::Statsd::TAG_LANG_INTERPRETER}:#{Ext::Meta::LANG_INTERPRETER}".freeze,
        "#{Ext::Statsd::TAG_LANG_VERSION}:#{Ext::Meta::LANG_VERSION}".freeze,
        "#{Ext::Statsd::TAG_TRACER_VERSION}:#{Ext::Meta::TRACER_VERSION}".freeze
      ].freeze
    }.freeze

    attr_accessor :statsd

    protected

    def distribution(stat, value, options = nil)
      return if statsd.nil?
      statsd.distribution(stat, value, statsd_options(options))
    end

    def increment(stat, options = nil)
      return if statsd.nil?
      statsd.increment(stat, statsd_options(options))
    end

    def time(stat, options = nil, &block)
      return yield if statsd.nil?
      statsd.time(stat, statsd_options(options), &block)
    end

    def statsd_options(options = nil)
      return DEFAULT_OPTIONS.dup if options.nil?
      options.dup.merge(tags: statsd_tags(options[:tags]))
    end

    def statsd_tags(tags = nil)
      return DEFAULT_TAGS.dup if tags.nil?
      DEFAULT_TAGS.dup.concat(tags)
    end
  end
end
