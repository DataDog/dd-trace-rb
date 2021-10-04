# typed: true
# frozen_string_literal: true

require 'time'
require 'ddtrace/utils'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/environment'
require 'ddtrace/ext/errors'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/priority'
require 'ddtrace/analytics'
require 'ddtrace/forced_tracing'
require 'ddtrace/diagnostics/health'
require 'ddtrace/utils/time'

module Datadog
  # Represents a logical unit of work in the system. Each trace consists of one or more spans.
  # Each span consists of a start time and a duration. For example, a span can describe the time
  # spent on a distributed call on a separate machine, or the time spent in a small component
  # within a larger operation. Spans can be nested within each other, and in those instances
  # will have a parent-child relationship.
  #
  # rubocop:disable Metrics/ClassLength
  class Span
    prepend Analytics::Span
    prepend ForcedTracing::Span

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

    # This limit is for numeric tags because uint64 could end up rounded.
    NUMERIC_TAG_SIZE_RANGE = (-1 << 53..1 << 53).freeze

    # Some associated values should always be sent as Tags, never as Metrics, regardless
    # if their value is numeric or not.
    # The Datadog agent will look for these values only as Tags, not Metrics.
    # @see https://github.com/DataDog/datadog-agent/blob/2ae2cdd315bcda53166dd8fa0dedcfc448087b9d/pkg/trace/stats/aggregation.go#L13-L17
    ENSURE_AGENT_TAGS = {
      Ext::DistributedTracing::ORIGIN_KEY => true,
      Ext::Environment::TAG_VERSION => true,
      Ext::HTTP::STATUS_CODE => true,
      Ext::NET::TAG_HOSTNAME => true
    }.freeze

    attr_accessor :name, :service, :resource, :span_type,
                  :span_id, :trace_id, :parent_id,
                  :status, :sampled,
                  :tracer, :context

    attr_reader :parent, :start_time, :end_time

    attr_writer :duration

    # Create a new span linked to the given tracer. Call the \Tracer method <tt>start_span()</tt>
    # and then <tt>finish()</tt> once the tracer operation is over.
    #
    # * +service+: the service name for this span
    # * +resource+: the resource this span refers, or +name+ if it's missing.
    #     +nil+ can be used as a placeholder, when the resource value is not yet known at +#initialize+ time.
    # * +span_type+: the type of the span (such as +http+, +db+ and so on)
    # * +parent_id+: the identifier of the parent span
    # * +trace_id+: the identifier of the root span for this trace
    # * +context+: the context of the span
    def initialize(tracer, name, options = {})
      @tracer = tracer

      @name = name
      @service = options.fetch(:service, nil)
      @resource = options.fetch(:resource, name)
      @span_type = options.fetch(:span_type, nil)

      @span_id = Datadog::Utils.next_id
      @parent_id = options.fetch(:parent_id, 0)
      @trace_id = options.fetch(:trace_id, Datadog::Utils.next_id)

      @context = options.fetch(:context, nil)

      @meta = {}
      @metrics = {}
      @status = 0

      @parent = nil
      @sampled = true

      @allocation_count_start = now_allocations
      @allocation_count_finish = @allocation_count_start

      # start_time and end_time track wall clock. In Ruby, wall clock
      # has less accuracy than monotonic clock, so if possible we look to only use wall clock
      # to measure duration when a time is supplied by the user, or if monotonic clock
      # is unsupported.
      @start_time = nil
      @end_time = nil

      # duration_start and duration_end track monotonic clock, and may remain nil in cases where it
      # is known that we have to use wall clock to measure duration.
      @duration_start = nil
      @duration_end = nil
    end

    # Set the given key / value tag pair on the span. Keys and values
    # must be strings. A valid example is:
    #
    #   span.set_tag('http.method', request.method)
    def set_tag(key, value = nil)
      # Keys must be unique between tags and metrics
      @metrics.delete(key)

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
        @meta[key] = value.to_s
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
      @meta.delete(key)
    end

    # Return the tag with the given key, nil if it doesn't exist.
    def get_tag(key)
      @meta[key] || @metrics[key]
    end

    # This method sets a tag with a floating point value for the given key. It acts
    # like `set_tag()` and it simply add a tag without further processing.
    def set_metric(key, value)
      # Keys must be unique between tags and metrics
      @meta.delete(key)

      # enforce that the value is a floating point number
      value = Float(value)
      @metrics[key] = value
    rescue StandardError => e
      Datadog.logger.debug("Unable to set the metric #{key}, ignoring it. Caused by: #{e}")
    end

    # This method removes a metric for the given key. It acts like {#remove_tag}.
    def clear_metric(key)
      @metrics.delete(key)
    end

    # Return the metric with the given key, nil if it doesn't exist.
    def get_metric(key)
      @metrics[key] || @meta[key]
    end

    # Mark the span with the given error.
    def set_error(e)
      e = Error.build_from(e)

      @status = Ext::Errors::STATUS
      set_tag(Ext::Errors::TYPE, e.type) unless e.type.empty?
      set_tag(Ext::Errors::MSG, e.message) unless e.message.empty?
      set_tag(Ext::Errors::STACK, e.backtrace) unless e.backtrace.empty?
    end

    # Mark the span started at the current time.
    def start(start_time = nil)
      # A span should not be started twice. However, this is existing
      # behavior and so we maintain it for backward compatibility for those
      # who are using async manual instrumentation that may rely on this

      @start_time = start_time || Utils::Time.now.utc
      @duration_start = start_time.nil? ? duration_marker : nil

      self
    end

    # for backwards compatibility
    def start_time=(time)
      time.tap { start(time) }
    end

    # for backwards compatibility
    def end_time=(time)
      time.tap { finish(time) }
    end

    # Mark the span finished at the current time and submit it.
    def finish(finish_time = nil)
      # A span should not be finished twice. Note that this is not thread-safe,
      # finish is called from multiple threads, a given span might be finished
      # several times. Again, one should not do this, so this test is more a
      # fallback to avoid very bad things and protect you in most common cases.
      return if finished?

      @allocation_count_finish = now_allocations

      now = Utils::Time.now.utc

      # Provide a default start_time if unset.
      # Using `now` here causes duration to be 0; this is expected
      # behavior when start_time is unknown.
      start(finish_time || now) unless started?

      @end_time = finish_time || now
      @duration_end = finish_time.nil? ? duration_marker : nil

      # Finish does not really do anything if the span is not bound to a tracer and a context.
      return self if @tracer.nil? || @context.nil?

      # spans without a service would be dropped, so here we provide a default.
      # This should really never happen with integrations in contrib, as a default
      # service is always set. It's only for custom instrumentation.
      @service ||= (@tracer && @tracer.default_service)

      begin
        @context.close_span(self)
        @tracer.record(self)
      rescue StandardError => e
        Datadog.logger.debug("error recording finished trace: #{e}")
        Datadog.health_metrics.error_span_finish(1, tags: ["error:#{e.class.name}"])
      end
      self
    end

    # Return a string representation of the span.
    def to_s
      "Span(name:#{@name},sid:#{@span_id},tid:#{@trace_id},pid:#{@parent_id})"
    end

    # DEPRECATED: remove this function in the next release, replaced by ``parent=``
    def set_parent(parent)
      self.parent = parent
    end

    # Set this span's parent, inheriting any properties not explicitly set.
    # If the parent is nil, set the span zero values.
    def parent=(parent)
      @parent = parent

      if parent.nil?
        @trace_id = @span_id
        @parent_id = 0
      else
        @trace_id = parent.trace_id
        @parent_id = parent.span_id
        @service ||= parent.service
        @sampled = parent.sampled
      end
    end

    def allocations
      @allocation_count_finish - @allocation_count_start
    end

    # Return the hash representation of the current span.
    def to_hash
      h = {
        span_id: @span_id,
        parent_id: @parent_id,
        trace_id: @trace_id,
        name: @name,
        service: @service,
        resource: @resource,
        type: @span_type,
        meta: @meta,
        metrics: @metrics,
        allocations: allocations,
        error: @status
      }

      if finished?
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

      if finished?
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
      packer.write(@span_id)
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
      packer.write(@span_type)
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
        q.text "Span ID: #{@span_id}\n"
        q.text "Parent ID: #{@parent_id}\n"
        q.text "Trace ID: #{@trace_id}\n"
        q.text "Type: #{@span_type}\n"
        q.text "Service: #{@service}\n"
        q.text "Resource: #{@resource}\n"
        q.text "Error: #{@status}\n"
        q.text "Start: #{start_time}\n"
        q.text "End: #{end_time}\n"
        q.text "Duration: #{duration.to_f if finished?}\n"
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

    # Return whether the duration is started or not
    def started?
      !@start_time.nil?
    end

    # Return whether the duration is finished or not.
    def finished?
      !@end_time.nil?
    end

    def duration
      if @duration_end.nil? || @duration_start.nil?
        @end_time - @start_time
      else
        @duration_end - @duration_start
      end
    end

    private

    def duration_marker
      Utils::Time.get_time
    end

    if defined?(JRUBY_VERSION) || Gem::Version.new(RUBY_VERSION) < Gem::Version.new(VERSION::MINIMUM_RUBY_VERSION)
      def now_allocations
        0
      end
    elsif Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.2.0')
      def now_allocations
        GC.stat.fetch(:total_allocated_object)
      end
    else
      def now_allocations
        GC.stat(:total_allocated_objects)
      end
    end

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
