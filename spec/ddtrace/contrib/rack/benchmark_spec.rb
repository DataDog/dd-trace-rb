require 'rack'
require 'ddtrace'

require 'rack/test'
require 'spec/ddtrace/benchmark/support/benchmark_helper'

RSpec.describe 'Rack benchmark' do
  include Rack::Test::Methods

  let(:rack_options) { {} }
  let(:app) do
    app_routes = routes
    instrument = self.instrument

    Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware if instrument
      instance_eval(&app_routes)
    end.to_app
  end
  let(:instrument) { true }

  before do
    tracer = self.tracer
    Datadog.configure do |c|
      c.use :rack, rack_options
      c.tracer = tracer
    end
  end

  context 'with a 200 route' do
    let(:routes) do
      proc do
        map '/success/' do
          run(->(_env) { [200, { 'Content-Type' => 'text/html' }, ['OK']] })
        end
      end
    end

    describe 'GET request' do
      subject(:response) { get route }

      context 'with query string parameters' do
        let(:route) { '/success?foo=bar' }
        let(:rack_options) do
          super().merge(request_queuing: true, analytics_enabled: true,
                        headers: {
                          request: [Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID],
                          response: ['content-type']
                        })
        end

        before do
          header 'X-Request-Start', "t=#{Time.now.to_f}"
        end

        shared_context 'distributed tracing headers' do
          let(:trace_id) { '8694058539399423136' }
          let(:parent_id) { '3605612475141592985' }
          let(:sampling_priority) { Datadog::Ext::Priority::AUTO_KEEP.to_s }
          let(:origin) { 'synthetics' }

          before do
            header Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID, trace_id
            header Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID, parent_id
            header Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY, sampling_priority
            header Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN, origin
          end
        end

        context 'benchmark' do
          include_context 'distributed tracing headers'

          let(:tracer) { new_tracer(writer: writer) }
          let(:writer) { FauxWriter.new(call_original: false) }

          let(:steps) { [1] } # No need to run for many input sizes
          let(:ignore_files) { %r{(/spec/)} } # Remove objects created during specs from memory results

          def subject(_i)
            get '/success?foo=bar#frag'
            writer.clear # Ensure traces don't accumulate
          end

          context 'without instrumentation (baseline)' do
            let(:instrument) { false }

            include_examples 'benchmark'
          end

          context 'with instrumentation' do
            let(:instrument) { true }

            include_examples 'benchmark'
          end
        end
      end
    end
  end
end
