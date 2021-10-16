require 'forwardable'

require 'datadog/core/environment/identity'
require 'ddtrace/ext/analytics'
require 'ddtrace/ext/manual_tracing'
require 'ddtrace/ext/runtime'

require 'ddtrace/span'
require 'ddtrace/analytics'
require 'ddtrace/forced_tracing'

module Datadog
  # Represents the act of taking a span measurement.
  # It gives a Span a context which can be used to
  # manage and decorate the Span.
  # When completed, it yields the Span.
  class SpanOperation
    extend Forwardable

    FORWARDED_METHODS = [
      :allocations,
      :clear_metric,
      :clear_tag,
      :duration,
      :duration=,
      :end_time,
      :end_time=,
      :get_metric,
      :get_tag,
      :name,
      :name=,
      :parent_id,
      :parent_id=,
      :pretty_print,
      :resource,
      :resource=,
      :sampled,
      :sampled=,
      :service,
      :service=,
      :set_error,
      :set_metric,
      :set_parent,
      :set_tag,
      :set_tags,
      :span_id,
      :span_id=,
      :span_type,
      :span_type=,
      :start_time,
      :start_time=,
      :started?,
      :status,
      :status=,
      :stop,
      :stopped?,
      :to_hash,
      :to_json,
      :to_msgpack,
      :to_s,
      :trace_id,
      :trace_id=
    ].to_set.freeze

    attr_reader \
      :events,
      :parent

    # TODO: Deprecate use of #context.
    #       Context should be accessed from the tracer.
    #       This attribute is provided for backwards compatibility only.
    attr_accessor \
      :context,
      :span

    # Forward instance methods to Span except ones that would cause identity issues
    def_delegators :span, *FORWARDED_METHODS

    def initialize(span_name, options = {})
      # Resolve service name
      parent = options[:child_of]
      options[:service] ||= parent.service unless parent.nil?

      # Build span options
      span_options = {}
      span_options[:parent_id] = options[:parent_id] if options.key?(:parent_id)
      span_options[:resource] = options[:resource] if options.key?(:resource)
      span_options[:service] = options[:service] if options.key?(:service)
      span_options[:span_type] = options[:span_type] if options.key?(:span_type)
      span_options[:tags] = options[:tags] if options.key?(:tags)
      span_options[:trace_id] = options[:trace_id] if options.key?(:trace_id)

      @span = Span.new(span_name, **span_options)
      @context = options[:context]
      @events = options[:events] || Events.new

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
        # We must finish the span to trigger callbacks.
        # If the span failed to start, timing may be inaccurate,
        # but this is not really a serious concern.
        finish

        # Trigger the on_error event
        events.on_error.publish(self, e)

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

    # Set span parent
    def parent=(parent)
      @parent = parent
      span.parent = parent && parent.span
    end

    def start(start_time = nil)
      # A span should not be started twice. However, this is existing
      # behavior and so we maintain it for backward compatibility for those
      # who are using async manual instrumentation that may rely on this
      #
      # Don't overwrite the start time of a completed span.
      return self if stopped?

      # Trigger before_start event
      events.before_start.publish(self)

      # Start the span
      span.start(start_time)
    end

    def finish(end_time = nil)
      return span if finished?

      # Stop the span
      span.stop(end_time)

      # Trigger after_finish event
      events.after_finish.publish(self)

      span
    end

    def finished?
      span.stopped?
    end

    # Callback behavior
    class Events
      DEFAULT_ON_ERROR = proc { |span_op, error| span_op.set_error(error) unless span_op.nil? }

      attr_reader \
        :after_finish,
        :before_start,
        :on_error

      def initialize
        @after_finish = AfterFinish.new
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

    # Defines analytics behavior
    module Analytics
      def set_tag(key, value)
        case key
        when Ext::Analytics::TAG_ENABLED
          # If true, set rate to 1.0, otherwise set 0.0.
          value = value == true ? Ext::Analytics::DEFAULT_SAMPLE_RATE : 0.0
          Datadog::Analytics.set_sample_rate(self, value)
        when Ext::Analytics::TAG_SAMPLE_RATE
          Datadog::Analytics.set_sample_rate(self, value)
        else
          super if defined?(super)
        end
      end
    end

    # Defines forced tracing behavior
    module ForcedTracing
      def set_tag(key, value)
        # Configure sampling priority if they give us a forced tracing tag
        # DEV: Do not set if the value they give us is explicitly "false"
        case key
        when Ext::ManualTracing::TAG_KEEP
          Datadog::ForcedTracing.keep(self) unless value == false
        when Ext::ManualTracing::TAG_DROP
          Datadog::ForcedTracing.drop(self) unless value == false
        else
          # Otherwise, set the tag normally.
          super if defined?(super)
        end
      end
    end

    # Additional extensions
    prepend Analytics
    prepend ForcedTracing

    # Error when the span attempts to start again after being started
    class AlreadyStartedError < StandardError
      def message
        'Cannot measure an already started span!'.freeze
      end
    end
  end
end
