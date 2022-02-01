# typed: true
# frozen_string_literal: true

require 'datadog/core/utils'

require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/metadata'

module Datadog
  module Tracing
    # Represents a logical unit of work in the system. Each trace consists of one or more spans.
    # Each span consists of a start time and a duration. For example, a span can describe the time
    # spent on a distributed call on a separate machine, or the time spent in a small component
    # within a larger operation. Spans can be nested within each other, and in those instances
    # will have a parent-child relationship.
    # @public_api
    class Span
      include Metadata

      # The max value for a {Datadog::Tracing::Span} identifier.
      # Span and trace identifiers should be strictly positive and strictly inferior to this limit.
      #
      # Limited to +2<<62-1+ positive integers, as Ruby is able to represent such numbers "inline",
      # inside a +VALUE+ scalar, thus not requiring memory allocation.
      #
      # The range of IDs also has to consider portability across different languages and platforms.
      RUBY_MAX_ID = (1 << 62) - 1

      # While we only generate 63-bit integers due to limitations in other languages, we support
      # parsing 64-bit integers for distributed tracing since an upstream system may generate one
      EXTERNAL_MAX_ID = 1 << 64

      attr_accessor \
        :end_time,
        :id,
        :meta,
        :metrics,
        :name,
        :parent_id,
        :resource,
        :service,
        :type,
        :start_time,
        :status,
        :trace_id

      attr_writer \
        :duration

      # For backwards compatiblity
      # TODO: Deprecate and remove these.
      alias :span_id :id
      alias :span_type :type

      # Create a new span manually. Call the <tt>start()</tt> method to start the time
      # measurement and then <tt>stop()</tt> once the timing operation is over.
      #
      # * +service+: the service name for this span
      # * +resource+: the resource this span refers, or +name+ if it's missing.
      #     +nil+ can be used as a placeholder, when the resource value is not yet known at +#initialize+ time.
      # * +type+: the type of the span (such as +http+, +db+ and so on)
      # * +parent_id+: the identifier of the parent span
      # * +trace_id+: the identifier of the root span for this trace
      # TODO: Remove span_type
      def initialize(
        name,
        duration: nil,
        end_time: nil,
        id: nil,
        meta: nil,
        metrics: nil,
        parent_id: 0,
        resource: name,
        service: nil,
        span_type: nil,
        start_time: nil,
        status: 0,
        type: span_type,
        trace_id: nil
      )
        @name = name
        @service = service
        @resource = resource
        @type = type

        @id = id || Core::Utils.next_id
        @parent_id = parent_id || 0
        @trace_id = trace_id || Core::Utils.next_id

        @meta = meta || {}
        @metrics = metrics || {}
        @status = status || 0

        # start_time and end_time track wall clock. In Ruby, wall clock
        # has less accuracy than monotonic clock, so if possible we look to only use wall clock
        # to measure duration when a time is supplied by the user, or if monotonic clock
        # is unsupported.
        @start_time = start_time
        @end_time = end_time

        # duration_start and duration_end track monotonic clock, and may remain nil in cases where it
        # is known that we have to use wall clock to measure duration.
        @duration = duration
      end

      # Return whether the duration is started or not
      def started?
        !@start_time.nil?
      end

      # Return whether the duration is stopped or not.
      def stopped?
        !@end_time.nil?
      end
      alias :finished? :stopped?

      def duration
        return @duration if @duration
        return @end_time - @start_time if @start_time && @end_time
      end

      def set_error(e)
        @status = Metadata::Ext::Errors::STATUS
        super
      end

      # Spans with the same ID are considered the same span
      def ==(other)
        other.instance_of?(Span) &&
          @id == other.id
      end

      # Return a string representation of the span.
      def to_s
        "Span(name:#{@name},sid:#{@id},tid:#{@trace_id},pid:#{@parent_id})"
      end

      # Return the hash representation of the current span.
      # TODO: Change this to reflect attributes when serialization
      # isn't handled by this method.
      def to_hash
        h = {
          error: @status,
          meta: @meta,
          metrics: @metrics,
          name: @name,
          parent_id: @parent_id,
          resource: @resource,
          service: @service,
          span_id: @id,
          trace_id: @trace_id,
          type: @type
        }

        if stopped?
          h[:start] = start_time_nano
          h[:duration] = duration_nano
        end

        h
      end

      # Return a human readable version of the span
      def pretty_print(q)
        start_time = (self.start_time.to_f * 1e9).to_i
        end_time = (self.end_time.to_f * 1e9).to_i
        q.group 0 do
          q.breakable
          q.text "Name: #{@name}\n"
          q.text "Span ID: #{@id}\n"
          q.text "Parent ID: #{@parent_id}\n"
          q.text "Trace ID: #{@trace_id}\n"
          q.text "Type: #{@type}\n"
          q.text "Service: #{@service}\n"
          q.text "Resource: #{@resource}\n"
          q.text "Error: #{@status}\n"
          q.text "Start: #{start_time}\n"
          q.text "End: #{end_time}\n"
          q.text "Duration: #{duration.to_f}\n"
          q.group(2, 'Tags: [', "]\n") do
            q.breakable
            q.seplist @meta.each do |key, value|
              q.text "#{key} => #{value}"
            end
          end
          q.group(2, 'Metrics: [', ']') do
            q.breakable
            q.seplist @metrics.each do |key, value|
              q.text "#{key} => #{value}"
            end
          end
        end
      end

      private

      # Used for serialization
      # @return [Integer] in nanoseconds since Epoch
      def start_time_nano
        @start_time.to_i * 1000000000 + @start_time.nsec
      end

      # Used for serialization
      # @return [Integer] in nanoseconds since Epoch
      def duration_nano
        (duration * 1e9).to_i
      end
    end
  end
end
