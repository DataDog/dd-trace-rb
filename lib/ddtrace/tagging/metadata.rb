require 'ddtrace/ext/distributed'
require 'ddtrace/ext/errors'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'

module Datadog
  module Tagging
    # Adds metadata & metric tag behavior
    # @public_api
    module Metadata
      # This limit is for numeric tags because uint64 could end up rounded.
      NUMERIC_TAG_SIZE_RANGE = (-1 << 53..1 << 53).freeze

      # Some associated values should always be sent as Tags, never as Metrics, regardless
      # if their value is numeric or not.
      # The Datadog agent will look for these values only as Tags, not Metrics.
      # @see https://github.com/DataDog/datadog-agent/blob/2ae2cdd315bcda53166dd8fa0dedcfc448087b9d/pkg/trace/stats/aggregation.go#L13-L17
      ENSURE_AGENT_TAGS = {
        Ext::DistributedTracing::TAG_ORIGIN => true,
        Ext::Environment::TAG_VERSION => true,
        Ext::HTTP::STATUS_CODE => true,
        Ext::NET::TAG_HOSTNAME => true
      }.freeze
      # Return the tag with the given key, nil if it doesn't exist.
      def get_tag(key)
        meta[key] || metrics[key]
      end

      # Set the given key / value tag pair on the span. Keys and values
      # must be strings. A valid example is:
      #
      #   span.set_tag('http.method', request.method)
      def set_tag(key, value = nil)
        # Keys must be unique between tags and metrics
        metrics.delete(key)

        # DEV: This is necessary because the agent looks at `meta[key]`, not `metrics[key]`.
        value = value.to_s if ENSURE_AGENT_TAGS[key]

        # NOTE: Adding numeric tags as metrics is stop-gap support
        #       for numeric typed tags. Eventually they will become
        #       tags again.
        # Any numeric that is not an integer greater than max size is logged as a metric.
        # Everything else gets logged as a tag.
        if value.is_a?(Numeric) && !(value.is_a?(Integer) && !NUMERIC_TAG_SIZE_RANGE.cover?(value))
          set_metric(key, value)
        else
          meta[key.to_s] = value.to_s
        end
      rescue StandardError => e
        Datadog.logger.debug("Unable to set the tag #{key}, ignoring it. Caused by: #{e}")
      end

      # Sets tags from given hash, for each key in hash it sets the tag with that key
      # and associated value from the hash. It is shortcut for `set_tag`. Keys and values
      # of the hash must be strings. Note that nested hashes are not supported.
      # A valid example is:
      #
      #   span.set_tags({ "http.method" => "GET", "user.id" => "234" })
      def set_tags(tags)
        tags.each { |k, v| set_tag(k, v) }
      end

      # This method removes a tag for the given key.
      def clear_tag(key)
        meta.delete(key)
      end

      # Return the metric with the given key, nil if it doesn't exist.
      def get_metric(key)
        metrics[key] || meta[key]
      end

      # This method sets a tag with a floating point value for the given key. It acts
      # like `set_tag()` and it simply add a tag without further processing.
      def set_metric(key, value)
        # Keys must be unique between tags and metrics
        meta.delete(key)

        # enforce that the value is a floating point number
        value = Float(value)
        metrics[key.to_s] = value
      rescue StandardError => e
        Datadog.logger.debug("Unable to set the metric #{key}, ignoring it. Caused by: #{e}")
      end

      # This method removes a metric for the given key. It acts like {#clear_tag}.
      def clear_metric(key)
        metrics.delete(key)
      end

      # Mark the span with the given error.
      def set_error(e)
        e = Error.build_from(e)

        set_tag(Ext::Errors::TYPE, e.type) unless e.type.empty?
        set_tag(Ext::Errors::MSG, e.message) unless e.message.empty?
        set_tag(Ext::Errors::STACK, e.backtrace) unless e.backtrace.empty?
      end

      protected

      def meta
        @meta ||= {}
      end

      def metrics
        @metrics ||= {}
      end
    end
  end
end
