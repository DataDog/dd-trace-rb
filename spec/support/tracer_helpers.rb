require 'ddtrace/tracer'
require 'ddtrace/span'
require 'support/faux_writer'

module TracerHelpers
  # Return a test tracer instance with a faux writer.
  def get_test_tracer
    Datadog::Tracer.new(writer: FauxWriter.new)
  end

  # Return some test traces
  def get_test_traces(n)
    traces = []

    defaults = {
      service: 'test-app',
      resource: '/traces',
      span_type: 'web'
    }

    n.times do
      span1 = Datadog::Span.new(nil, 'client.testing', defaults).finish()
      span2 = Datadog::Span.new(nil, 'client.testing', defaults).finish()
      span2.set_parent(span1)
      traces << [span1, span2]
    end

    traces
  end

  # Return some test services
  def get_test_services
    { 'rest-api' => { 'app' => 'rails', 'app_type' => 'web' },
      'master' => { 'app' => 'postgres', 'app_type' => 'db' } }
  end
end
