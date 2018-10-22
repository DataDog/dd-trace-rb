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

    def increment(stat, options = nil)
      return if statsd.nil?
      statsd.increment(stat, merge_with_defaults(options))
    end

    private

    def merge_with_defaults(options)
      if options.nil?
        # Set default options
        DEFAULT_OPTIONS.dup
      else
        # Add tags to options
        options.dup.tap do |opts|
          opts[:tags] = if opts.key?(:tags)
                          opts[:tags].dup.concat(DEFAULT_TAGS)
                        else
                          DEFAULT_TAGS.dup
                        end
        end
      end
    end
  end
end
