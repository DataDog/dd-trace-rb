require 'ddtrace/tracer'
require 'ddtrace/span'
require 'support/faux_writer'

module TracerHelpers
  # Return a test tracer instance with a faux writer.
  def get_test_tracer(options = {})
    options = { writer: FauxWriter.new }.merge(options)
    Datadog::Tracer.new(options).tap do |tracer|
      # TODO: Let's try to get rid of this override, which has too much
      #       knowledge about the internal workings of the tracer.
      #       It is done to prevent the activation of priority sampling
      #       from wiping out the configured test writer, by replacing it.
      tracer.define_singleton_method(:configure) do |opts = {}|
        super(opts)

        # Re-configure the tracer with a new test writer
        # since priority sampling will wipe out the old test writer.
        unless @writer.is_a?(FauxWriter)
          @writer = if @sampler.is_a?(Datadog::PrioritySampler)
                      FauxWriter.new(priority_sampler: @sampler)
                    else
                      FauxWriter.new
                    end

          hostname = opts.fetch(:hostname, nil)
          port = opts.fetch(:port, nil)

          @writer.transport.hostname = hostname unless hostname.nil?
          @writer.transport.port = port unless port.nil?

          statsd = opts.fetch(:statsd, nil)
          unless statsd.nil?
            @writer.statsd = statsd
            @writer.transport.statsd = statsd
          end
        end
      end
    end
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
