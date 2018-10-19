require 'ddtrace/ext/meta'
require 'ddtrace/ext/statsd'

module Datadog
  # Behavior for sending statistics to Statsd
  module Metrics
    DEFAULT_OPTIONS = {
      tags: [
        "#{Ext::Statsd::TAG_LANG}:#{Ext::Meta::LANG}".freeze,
        "#{Ext::Statsd::TAG_LANG_INTERPRETER}:#{Ext::Meta::LANG_INTERPRETER}".freeze,
        "#{Ext::Statsd::TAG_LANG_VERSION}:#{Ext::Meta::LANG_VERSION}".freeze,
        "#{Ext::Statsd::TAG_TRACER_VERSION}:#{Ext::Meta::TRACER_VERSION}".freeze
      ].freeze
    }.freeze

    attr_accessor :statsd

    protected

    def increment(stat, options = nil)
      return if statsd.nil?
      options = options.nil? ? DEFAULT_OPTIONS : DEFAULT_OPTIONS.merge(options)
      statsd.increment(stat, options)
    end
  end
end
