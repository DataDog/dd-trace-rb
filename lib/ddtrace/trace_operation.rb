require 'ddtrace/ext/priority'

require 'datadog/core/environment/identity'

require 'ddtrace/event'
require 'ddtrace/span_operation'
require 'ddtrace/trace_segment'
require 'ddtrace/trace_digest'

module Datadog
  # Represents the act of tracing a series of operations,
  # by generating and collecting span measurements.
  # When completed, it yields a trace.
  #
  # Supports synchronous code flow *only*. Usage across
  # multiple threads will result in incorrect relationships.
  # For async support, a {Datadog::TraceOperation} should be employed
  # per execution context (e.g. Thread, etc.)
  #
  # rubocop:disable Metrics/ClassLength
  # @public_api
  class TraceOperation
    DEFAULT_MAX_LENGTH = 100_000

    attr_accessor \
      :agent_sample_rate,
      :hostname,
      :name,
      :origin,
      :rate_limiter_rate,
      :resource,
      :rule_sample_rate,
      :sample_rate,
      :sampling_priority,
      :service

    attr_reader \
      :active_span_count,
      :active_span,
      :id,
      :max_length,
      :parent_span_id

    attr_writer \
      :sampled

    def initialize(
      agent_sample_rate: nil,
      events: nil,
      hostname: nil,
      id: nil,
      max_length: DEFAULT_MAX_LENGTH,
      name: nil,
      origin: nil,
      parent_span_id: nil,
      rate_limiter_rate: nil,
      resource: nil,
      rule_sample_rate: nil,
      sample_rate: nil,
      sampled: nil,
      sampling_priority: nil,
      service: nil
    )
      # Attributes
      @events = events || Events.new
      @id = id || Core::Utils.next_id
      @max_length = max_length || DEFAULT_MAX_LENGTH
      @parent_span_id = parent_span_id
      @sampled = sampled.nil? ? false : sampled

      # Tags
      @agent_sample_rate = agent_sample_rate
      @hostname = hostname
      @name = name
      @origin = origin
      @rate_limiter_rate = rate_limiter_rate
      @resource = resource
      @rule_sample_rate = rule_sample_rate
      @sample_rate = sample_rate
      @sampling_priority = sampling_priority
      @service = service

      # State
      @root_span = nil
      @active_span = nil
      @active_span_count = 0
      @events = events || Events.new
      @finished = false
      @spans = []
    end

    def full?
      @max_length > 0 && @active_span_count >= @max_length
    end

    def finished_span_count
      @spans.length
    end

    def finished?
      @finished == true
    end

    def sampled?
      @sampled == true || (!@sampling_priority.nil? && @sampling_priority > 0)
    end

    def keep!
      self.sampled = true
      self.sampling_priority = Datadog::Ext::Priority::USER_KEEP
    end

    def reject!
      self.sampled = false
      self.sampling_priority = Datadog::Ext::Priority::USER_REJECT
    end

    def measure(op_name, **span_options, &block)
      # Don't allow more span measurements if the
      # trace is already completed. Prevents multiple
      # root spans with parent_span_id = 0.
      return yield(SpanOperation.new(op_name), TraceOperation.new) if finished? || full?

      # Create new span
      span_op = build_span(op_name, **span_options)

      # Start span measurement
      span_op.measure { |s| yield(s, self) }
    end

    def build_span(op_name, **span_options)
      begin
        # Resolve span options:
        # Parent, service name, etc.
        span_options = build_span_options(**span_options)

        # Build a new span operation
        Datadog::SpanOperation.new(op_name, **span_options)
      rescue StandardError => e
        Datadog.logger.debug { "Failed to build new span: #{e}" }

        # Return dummy span
        SpanOperation.new(op_name)
      end
    end

    def flush!
      finished = finished?

      # Copy out completed spans
      spans = @spans.dup
      @spans = []

      # Use them to build a trace
      build_trace(spans, !finished)
    end

    # Returns a set of trace headers used for continuing traces.
    # Used for propagation across execution contexts.
    # Data should reflect the active state of the trace.
    def to_digest
      # Resolve current span ID
      span_id = @active_span && @active_span.id
      span_id ||= @parent_span_id unless finished?

      TraceDigest.new(
        span_id: span_id,
        span_name: (@active_span && @active_span.name),
        span_resource: (@active_span && @active_span.resource),
        span_service: (@active_span && @active_span.service),
        span_type: (@active_span && @active_span.type),
        trace_hostname: @hostname,
        trace_id: @id,
        trace_name: @name,
        trace_origin: @origin,
        trace_process_id: Datadog::Core::Environment::Identity.pid,
        trace_resource: @resource,
        trace_runtime_id: Datadog::Core::Environment::Identity.id,
        trace_sampling_priority: @sampling_priority,
        trace_service: @service
      ).freeze
    end

    # Returns a copy of this trace suitable for forks (w/o spans.)
    # Used for continuation of traces across forks.
    def fork_clone
      self.class.new(
        agent_sample_rate: @agent_sample_rate,
        events: (@events && @events.dup),
        hostname: (@hostname && @hostname.dup),
        id: @id,
        max_length: @max_length,
        name: (@name && @name.dup),
        origin: (@origin && @origin.dup),
        parent_span_id: (@active_span && @active_span.id) || @parent_span_id,
        rate_limiter_rate: @rate_limiter_rate,
        resource: (@resource && @resource.dup),
        rule_sample_rate: @rule_sample_rate,
        sample_rate: @sample_rate,
        sampled: @sampled,
        sampling_priority: @sampling_priority,
        service: (@service && @service.dup)
      )
    end

    # Callback behavior
    class Events
      include Datadog::Events

      attr_reader \
        :span_before_start,
        :span_finished,
        :trace_finished

      def initialize
        @span_before_start = SpanBeforeStart.new
        @span_finished = SpanFinished.new
        @trace_finished = TraceFinished.new
      end

      # Triggered before a span starts.
      class SpanBeforeStart < Datadog::Event
        def initialize
          super(:span_before_start)
        end
      end

      # Triggered when a span finishes, regardless of error.
      class SpanFinished < Datadog::Event
        def initialize
          super(:span_finished)
        end
      end

      # Triggered when the trace finishes, regardless of error.
      class TraceFinished < Datadog::Event
        def initialize
          super(:trace_finished)
        end
      end
    end

    private

    attr_reader \
      :events,
      :root_span

    def activate_span!(span_op)
      parent = @active_span

      span_op.send(:parent=, parent) unless parent.nil?

      @active_span = span_op

      set_root_span!(span_op) unless root_span
    end

    def deactivate_span!(span_op)
      # Set parent to closest unfinished ancestor span.
      # Prevents wrong span from being set as the active span
      # when spans finish out of order.
      span_op = span_op.send(:parent) while !span_op.nil? && span_op.finished?
      @active_span = span_op
    end

    def start_span(span_op)
      begin
        activate_span!(span_op)

        # Update active span count
        @active_span_count += 1

        # Publish :span_before_start event
        events.span_before_start.publish(span_op, self)
      rescue StandardError => e
        Datadog.logger.debug { "Error starting span on trace: #{e} Backtrace: #{e.backtrace.first(3)}" }
      end
    end

    def finish_span(span, span_op, parent)
      begin
        # Save finished span & root span
        @spans << span unless span.nil?

        # Deactivate the span, re-activate parent.
        deactivate_span!(span_op)

        # Set finished, to signal root span has completed.
        @finished = true if span_op == @root_span

        # Update active span count
        @active_span_count -= 1

        # Publish :span_finished event
        events.span_finished.publish(span, self)

        # Publish :trace_finished event
        events.trace_finished.publish(self) if finished?
      rescue StandardError => e
        Datadog.logger.debug { "Error finishing span on trace: #{e} Backtrace: #{e.backtrace.first(3)}" }
      end
    end

    # Track the root span
    def set_root_span!(span)
      return if span.nil? || root_span

      @root_span = span

      # Auto populate these attributes if
      # they haven't been set yet.
      @name ||= span.name
      @resource ||= span.resource
      @service ||= span.service
    end

    def build_span_options(
      events: nil,
      on_error: nil,
      resource: nil,
      service: nil,
      start_time: nil,
      tags: nil,
      type: nil
    )
      # Add default options
      options = { trace_id: @id }
      options[:on_error] = on_error unless on_error.nil?
      options[:resource] = resource unless resource.nil?
      options[:service] = service unless service.nil?
      options[:start_time] = start_time unless start_time.nil?
      options[:tags] = tags unless tags.nil?
      options[:type] = type unless type.nil?

      # Use active span's span ID if available. Otherwise, the parent span ID.
      # Necessary when this trace continues from another, e.g. distributed trace.
      if (parent = @active_span)
        options[:child_of] = parent
        options[:parent_id] = parent.id
      else
        options[:parent_id] = @parent_span_id || 0
      end

      # Build events
      events ||= SpanOperation::Events.new
      options[:events] = events

      # Before start: activate the span, publish events.
      events.before_start.subscribe(:trace_before_span_start) do |span_op|
        start_span(span_op)
      end

      # After finish: deactivate the span, record, publish events.
      events.after_finish.subscribe(:trace_span_finished) do |span, span_op|
        finish_span(span, span_op, parent)
      end

      options
    end

    def build_trace(spans, partial = false)
      TraceSegment.new(
        spans,
        agent_sample_rate: @agent_sample_rate,
        hostname: @hostname,
        id: @id,
        lang: Datadog::Core::Environment::Identity.lang,
        origin: @origin,
        process_id: Datadog::Core::Environment::Identity.pid,
        rate_limiter_rate: @rate_limiter_rate,
        rule_sample_rate: @rule_sample_rate,
        runtime_id: Datadog::Core::Environment::Identity.id,
        sample_rate: @sample_rate,
        sampling_priority: @sampling_priority,
        name: @name,
        resource: @resource,
        service: @service,
        root_span_id: !partial ? @root_span && @root_span.id : nil
      )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
