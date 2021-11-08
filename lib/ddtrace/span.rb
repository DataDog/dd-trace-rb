# typed: true
# frozen_string_literal: true

require 'ddtrace/ext/errors'
require 'ddtrace/utils'
require 'ddtrace/tagging'

module Datadog
  # Represents a logical unit of work in the system. Each trace consists of one or more spans.
  # Each span consists of a start time and a duration. For example, a span can describe the time
  # spent on a distributed call on a separate machine, or the time spent in a small component
  # within a larger operation. Spans can be nested within each other, and in those instances
  # will have a parent-child relationship.
  #
  # rubocop:disable Metrics/ClassLength
  class Span
    include Tagging

    # The max value for a \Span identifier.
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
      :allocations,
      :end_time,
      :id,
      :meta,
      :metrics,
      :name,
      :parent_id,
      :resource,
      :sampled,
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
      allocations: 0,
      duration: nil,
      end_time: nil,
      id: nil,
      meta: nil,
      metrics: nil,
      parent_id: 0,
      resource: name,
      sampled: true,
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

      @id = id || Datadog::Utils.next_id
      @parent_id = parent_id || 0
      @trace_id = trace_id || Datadog::Utils.next_id

      @meta = meta || {}
      @metrics = metrics || {}
      @status = status || 0

      @sampled = sampled.nil? ? true : sampled

      @allocations = allocations || 0

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
      @status = Datadog::Ext::Errors::STATUS
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
        allocations: @allocations,
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

    # MessagePack serializer interface. Making this object
    # respond to `#to_msgpack` allows it to be automatically
    # serialized by MessagePack.
    #
    # This is more efficient than doing +MessagePack.pack(span.to_hash)+
    # as we don't have to create an intermediate Hash.
    #
    # @param packer [MessagePack::Packer] serialization buffer, can be +nil+ with JRuby
    def to_msgpack(packer = nil)
      # As of 1.3.3, JRuby implementation doesn't pass an existing packer
      packer ||= MessagePack::Packer.new

      if stopped?
        packer.write_map_header(13) # Set header with how many elements in the map

        packer.write('start')
        packer.write(start_time_nano)

        packer.write('duration')
        packer.write(duration_nano)
      else
        packer.write_map_header(11) # Set header with how many elements in the map
      end

      # DEV: We use strings as keys here, instead of symbols, as
      # DEV: MessagePack will ultimately convert them to strings.
      # DEV: By providing strings directly, we skip this indirection operation.
      packer.write('span_id')
      packer.write(@id)
      packer.write('parent_id')
      packer.write(@parent_id)
      packer.write('trace_id')
      packer.write(@trace_id)
      packer.write('name')
      packer.write(@name)
      packer.write('service')
      packer.write(@service)
      packer.write('resource')
      packer.write(@resource)
      packer.write('type')
      packer.write(@type)
      packer.write('meta')
      packer.write(@meta)
      packer.write('metrics')
      packer.write(@metrics)
      packer.write('allocations')
      packer.write(allocations)
      packer.write('error')
      packer.write(@status)
      packer
    end

    # JSON serializer interface.
    # Used by older version of the transport.
    def to_json(*args)
      to_hash.to_json(*args)
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
        q.text "Allocations: #{allocations}\n"
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
