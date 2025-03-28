require 'datadog/tracing/tracer'
require 'datadog/tracing/correlation'
require 'datadog/tracing/trace_operation'
require 'support/faux_writer'
require 'datadog/tracing/utils'

module TracerHelpers
  # Return a test tracer instance with a faux writer.
  def tracer
    @tracer ||= new_tracer
  end

  def test_agent_settings
    settings = Datadog::Core::Configuration::Settings.new
    Datadog::Core::Configuration::AgentSettingsResolver.call(settings)
  end

  def new_tracer(options = {})
    logger = options[:logger] || Datadog.logger
    writer = FauxWriter.new(
      transport: Datadog::Tracing::Transport::HTTP.default(agent_settings: test_agent_settings, logger: logger) do |t|
        t.adapter :test
      end
    )

    options = { writer: writer }.merge(options)
    Datadog::Tracing::Tracer.new(**options)
  end

  def get_test_writer(options = {})
    options = {
      transport: Datadog::Tracing::Transport::HTTP.default(agent_settings: test_agent_settings, logger: logger) do |t|
        t.adapter :test
      end
    }.merge(options)

    FauxWriter.new(options)
  end

  # Return some test traces
  def get_test_traces(n, service: 'test-app', resource: '/traces', type: 'web')
    traces = []

    n.times do
      trace_op = Datadog::Tracing::TraceOperation.new

      trace_op.measure('client.testing', service: service, resource: resource, type: type) do
        trace_op.measure('client.testing', service: service, resource: resource, type: type) do
        end
      end

      traces << trace_op.flush!
    end

    traces
  end

  # Return some test services
  def get_test_services
    { 'rest-api' => { 'app' => 'rails', 'app_type' => 'web' },
      'master' => { 'app' => 'postgres', 'app_type' => 'db' } }
  end

  def writer
    tracer.writer
  end

  def traces
    @traces ||= writer.traces
  end

  def spans
    @spans ||= writer.spans
  end

  def fetch_spans
    writer.spans(:keep)
  end

  # Returns the only trace in the current tracer writer.
  #
  # This method will not allow for ambiguous use,
  # meaning it will throw an error when more than
  # one span is available.
  def trace
    @trace ||= begin
      expect(traces).to have(1).item, "Requested the only trace, but #{traces.size} traces are available"
      traces.first
    end
  end

  # Returns the only span in the current tracer writer.
  #
  # This method will not allow for ambiguous use,
  # meaning it will throw an error when more than
  # one span is available.
  def span
    @span ||= begin
      expect(spans).to have(1).item, "Requested the only span, but #{spans.size} spans are available"
      spans.first
    end
  end

  def clear_traces!
    writer.spans(:clear)

    @traces = nil
    @trace = nil
    @spans = nil
    @span = nil
  end

  def tracer_shutdown!
    if defined?(@use_real_tracer) && @use_real_tracer
      Datadog::Tracing.shutdown!
    elsif defined?(@tracer) && @tracer
      @tracer.shutdown!
      @tracer = nil
    end

    without_warnings { Datadog.send(:reset!) }
  end

  # Wraps call to Tracing::Utils::TraceId.to_low_order for better test readability
  def low_order_trace_id(trace_id)
    Datadog::Tracing::Utils::TraceId.to_low_order(trace_id)
  end

  ## Wraps call to Datadog::Tracing::Correlation.format_trace_id_128 for better test readability
  def format_for_correlation(trace_id)
    Datadog::Tracing::Correlation.format_trace_id_128(trace_id)
  end

  # Wraps call to Tracing::Utils::TraceId.to_high_order and converts to hex
  # for better test readability
  def high_order_hex_trace_id(trace_id)
    format('%016x', Datadog::Tracing::Utils::TraceId.to_high_order(trace_id))
  end
end
