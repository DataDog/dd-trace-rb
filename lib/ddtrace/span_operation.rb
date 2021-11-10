require 'forwardable'
require 'time'

require 'datadog/core/environment/identity'
require 'ddtrace/ext/manual_tracing'
require 'ddtrace/ext/errors'
require 'ddtrace/ext/runtime'

require 'ddtrace/span'
require 'ddtrace/tagging'
require 'ddtrace/utils'

module Datadog
  # Represents the act of taking a span measurement.
  # It gives a Span a context which can be used to
  # build a Span. When completed, it yields the Span.
  #
  # rubocop:disable Metrics/ClassLength
  class SpanOperation
    include Tagging

    # Span attributes
    # NOTE: In the future, we should drop the me
    attr_reader \
      :end_time,
      :id,
      :parent_id,
      :start_time,
      :trace_id

    attr_accessor \
      :name,
      :resource,
      :sampled,
      :service,
      :type,
      :status

    # For backwards compatiblity
    # TODO: Deprecate and remove these.
    alias :span_id :id
    alias :span_type :type
    alias :span_type= :type=

    # SpanOperation attributes
    # TODO: Deprecate use of #parent.
    #       Instrumentation should not inspect trace structure,
    #       or rely upon a parent span; it might get mutated or finished.
    #       This attribute is provided for backwards compatibility only.
    # TODO: Deprecate use of #context.
    #       Context should be accessed from the tracer.
    #       This attribute is provided for backwards compatibility only.
    attr_reader \
      :parent,
      :context

    # TODO: Remove span_type
    def initialize(
      name,
      child_of: nil,
      context: nil,
      parent_id: 0,
      resource: name,
      service: nil,
      span_type: nil,
      start_time: nil,
      tags: nil,
      trace_id: nil,
      type: span_type
    )
      # Resolve service name
      parent = child_of
      service ||= parent.service unless parent.nil?

      # Set span attributes
      @name = name
      @service = service
      @resource = resource
      @type = type

      @id = Utils.next_id
      @parent_id = parent_id || 0
      @trace_id = trace_id || Utils.next_id

      @status = 0
      @sampled = true

      @allocation_count_start = now_allocations
      @allocation_count_stop = @allocation_count_start

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

      # Set tags if provided.
      set_tags(tags) if tags

      if parent.nil?
        # Root span: set default tags.
        set_tag(Datadog::Ext::Runtime::TAG_PID, Process.pid)
        set_tag(Datadog::Ext::Runtime::TAG_ID, Datadog::Core::Environment::Identity.id)
      else
        # Only set parent if explicitly provided.
        # We don't want it to override context-derived
        # IDs if it's a distributed trace w/o a parent span.
        self.parent = parent
      end

      # Some other SpanOperation-specific behavior
      @context = context
      @events = events || Events.new
      @span = nil

      # Start the span with start time, if given.
      start(start_time) if start_time
    end

    def measure
      raise ArgumentError, 'Must provide block to measure!' unless block_given?
      # TODO: Should we just invoke the block and skip tracing instead?
      raise AlreadyStartedError if started?

      return_value = nil

      begin
        # If span fails to start, don't prevent the operation from
        # running, to minimize impact on normal application function.
        begin
          start
        rescue StandardError => e
          Datadog.logger.debug("Failed to start span: #{e}")
        ensure
          # We should yield to the provided block when possible, as this
          # block is application code that we don't want to hinder.
          # * We don't yield during a fatal error, as the application is likely trying to
          #   end its execution (either due to a system error or graceful shutdown).
          return_value = yield(self) unless e && !e.is_a?(StandardError)
        end
      # rubocop:disable Lint/RescueException
      # Here we really want to catch *any* exception, not only StandardError,
      # as we really have no clue of what is in the block,
      # and it is user code which should be executed no matter what.
      # It's not a problem since we re-raise it afterwards so for example a
      # SignalException::Interrupt would still bubble up.
      rescue Exception => e
        # Stop the span first, so timing is a more accurate.
        # If the span failed to start, timing may be inaccurate,
        # but this is not really a serious concern.
        stop

        # Trigger the on_error event
        events.on_error.publish(self, e)

        # We must finish the span to trigger callbacks,
        # and build the final span.
        finish

        raise e
      # Use an ensure block here to make sure the span closes.
      # NOTE: It's not sufficient to use "else": when a function
      #       uses "return", it will skip "else".
      ensure
        # Finish the span
        # NOTE: If an error was raised, this "finish" might be redundant.
        finish unless finished?
      end
      # rubocop:enable Lint/RescueException

      return_value
    end

    def start(start_time = nil)
      # Don't overwrite the start time of a started span.
      return self if started?

      # If time provided, set it but don't trigger
      # "before_start" as the span has already started.
      if start_time
        @start_time = start_time
        return self
      end

      # Trigger before_start event
      events.before_start.publish(self)

      # Start the span
      @start_time = Utils::Time.now.utc
      @duration_start = duration_marker

      self
    end

    # Mark the span stopped at the current time
    def stop(stop_time = nil)
      # A span should not be stopped twice. Note that this is not thread-safe,
      # stop is called from multiple threads, a given span might be stopped
      # several times. Again, one should not do this, so this test is more a
      # fallback to avoid very bad things and protect you in most common cases.
      return if stopped?

      @allocation_count_stop = now_allocations

      now = Utils::Time.now.utc

      # Provide a default start_time if unset.
      # Using `now` here causes duration to be 0; this is expected
      # behavior when start_time is unknown.
      start(stop_time || now) unless started?

      @end_time = stop_time || now
      @duration_end = stop_time.nil? ? duration_marker : nil

      # Trigger after_stop event
      events.after_stop.publish(self)

      self
    end

    # Return whether the duration is started or not
    def started?
      !@start_time.nil?
    end

    # Return whether the duration is stopped or not.
    def stopped?
      !@end_time.nil?
    end

    # for backwards compatibility
    def start_time=(time)
      time.tap { start(time) }
    end

    # for backwards compatibility
    def end_time=(time)
      time.tap { stop(time) }
    end

    def finish(end_time = nil)
      # Returned memoized span if already finished
      return span if finished?

      # Stop timing
      stop(end_time)

      # Build span
      # Memoize for performance reasons
      @span = build_span

      # Trigger after_finish event
      events.after_finish.publish(span, self)

      span
    end

    def finished?
      !span.nil?
    end

    def duration
      return @duration_end - @duration_start if @duration_start && @duration_end
      return @end_time - @start_time if @start_time && @end_time
    end

    def allocations
      @allocation_count_stop - @allocation_count_start
    end

    def set_error(e)
      @status = Datadog::Ext::Errors::STATUS
      super
    end

    # Return a string representation of the span.
    def to_s
      "SpanOperation(name:#{@name},sid:#{@id},tid:#{@trace_id},pid:#{@parent_id})"
    end

    # Return the hash representation of the current span.
    def to_hash
      h = {
        allocations: allocations,
        error: @status,
        id: @id,
        meta: meta,
        metrics: metrics,
        name: @name,
        parent_id: @parent_id,
        resource: @resource,
        service: @service,
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
        q.text "Duration: #{duration.to_f if stopped?}\n"
        q.text "Allocations: #{allocations}\n"
        q.group(2, 'Tags: [', "]\n") do
          q.breakable
          q.seplist meta.each do |key, value|
            q.text "#{key} => #{value}"
          end
        end
        q.group(2, 'Metrics: [', ']') do
          q.breakable
          q.seplist metrics.each do |key, value|
            q.text "#{key} => #{value}"
          end
        end
      end
    end

    # Callback behavior
    class Events
      DEFAULT_ON_ERROR = proc { |span_op, error| span_op.set_error(error) unless span_op.nil? }

      attr_reader \
        :after_finish,
        :after_stop,
        :before_start,
        :on_error

      def initialize
        @after_finish = AfterFinish.new
        @after_stop = AfterStop.new
        @before_start = BeforeStart.new
        @on_error = OnError.new

        # Set default error behavior
        on_error.subscribe(:default, &DEFAULT_ON_ERROR)
      end

      # Triggered when the span is finished, regardless of error.
      class AfterFinish < Datadog::Event
        def initialize
          super(:after_finish)
        end
      end

      # Triggered when the span is stopped, regardless of error.
      class AfterStop < Datadog::Event
        def initialize
          super(:after_stop)
        end
      end

      # Triggered just before the span is started.
      class BeforeStart < Datadog::Event
        def initialize
          super(:before_start)
        end
      end

      # Triggered when the span raises an error during measurement.
      class OnError < Datadog::Event
        def initialize
          super(:on_error)
        end
      end
    end

    # Error when the span attempts to start again after being started
    class AlreadyStartedError < StandardError
      def message
        'Cannot measure an already started span!'.freeze
      end
    end

    private

    # Keep span reference private: we don't want users
    # modifying the finalized span from the operation after
    # it has been finished.
    attr_reader \
      :span,
      :events

    attr_writer \
      :context

    # Create a Span from the operation which represents
    # the finalized measurement. We #dup here to prevent
    # mutation by reference; when this span is returned,
    # we don't want this SpanOperation to modify it further.
    def build_span
      Span.new(
        @name && @name.dup,
        allocations: allocations,
        duration: duration,
        end_time: @end_time,
        id: @id,
        meta: meta && meta.dup,
        metrics: metrics && metrics.dup,
        parent_id: @parent_id,
        resource: @resource && @resource.dup,
        sampled: @sampled,
        service: @service && @service.dup,
        start_time: @start_time,
        status: @status,
        type: @type && @type.dup,
        trace_id: @trace_id
      )
    end

    # Set this span's parent, inheriting any properties not explicitly set.
    # If the parent is nil, set the span as the root span.
    #
    # DEV: This method creates a false expectation that
    # `self.parent.id == self.parent_id`, which is not the case
    # for distributed traces, as the parent Span object does not exist
    # in this application. `#parent_id` is the only reliable parent
    # identifier. We should remove the ability to set a parent Span
    # object in the future.
    def parent=(parent)
      @parent = parent

      if parent.nil?
        @trace_id = @id
        @parent_id = 0
      else
        @trace_id = parent.trace_id
        @parent_id = parent.id
        @service ||= parent.service
        @sampled = parent.sampled
      end
    end

    def duration_marker
      Utils::Time.get_time
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
  end
  # rubocop:enable Metrics/ClassLength
end
