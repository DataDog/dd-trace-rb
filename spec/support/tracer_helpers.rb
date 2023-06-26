require 'datadog/tracing/tracer'
require 'datadog/tracing/trace_operation'
require 'support/faux_writer'

module TracerHelpers
  # Return a test tracer instance with a faux writer.
  def tracer
    @tracer ||= new_tracer
  end

  def new_tracer(options = {})
    writer = FauxWriter.new(
      transport: Datadog::Transport::HTTP.default do |t|
        t.adapter :test
      end
    )

    options = { writer: writer }.merge(options)
    Datadog::Tracing::Tracer.new(**options)
  end

  def get_test_writer(options = {})
    options = {
      transport: Datadog::Transport::HTTP.default do |t|
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
end
