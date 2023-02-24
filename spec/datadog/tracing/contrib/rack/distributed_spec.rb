require 'datadog/tracing/contrib/support/spec_helper'

require 'rack/test'
require 'rack'

require 'datadog/tracing/sampling/ext'
require 'ddtrace'
require 'datadog/tracing/contrib/rack/middlewares'

RSpec.describe 'Rack integration distributed tracing' do
  include Rack::Test::Methods

  let(:rack_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rack, rack_options
    end
  end

  after { Datadog.registry[:rack].reset_configuration! }

  shared_context 'an incoming HTTP request' do
    subject(:response) { get '/' }

    let(:app) do
      Rack::Builder.new do
        use Datadog::Tracing::Contrib::Rack::TraceMiddleware

        map '/' do
          run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
        end
      end.to_app
    end
  end

  shared_context 'distributed tracing headers' do
    let(:trace_id) { 8694058539399423136 }
    let(:parent_id) { 3605612475141592985 }
    let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP }
    let(:origin) { 'synthetics' }

    before do
      header 'x-datadog-trace-id', trace_id
      header 'x-datadog-parent-id', parent_id
      header 'x-datadog-sampling-priority', sampling_priority
      header 'x-datadog-origin', origin
    end
  end

  shared_context 'no distributed tracing headers' do
    let(:trace_id) { nil }
    let(:parent_id) { nil }
    let(:sampling_priority) { nil }
    let(:origin) { nil }
  end

  shared_examples_for 'a Rack request with distributed tracing' do
    it 'produces a distributed Rack trace' do
      is_expected.to be_ok
      expect(span).to_not be nil
      expect(span.name).to eq('rack.request')
      expect(span.trace_id).to eq(trace_id)
      expect(span.parent_id).to eq(parent_id)
      expect(trace.sampling_priority).to eq(sampling_priority)
      expect(trace.origin).to eq(origin)
    end
  end

  shared_examples_for 'a Rack request without distributed tracing' do
    it 'produces a non-distributed Rack trace' do
      is_expected.to be_ok
      expect(span).to_not be nil
      expect(span.name).to eq('rack.request')
      expect(span.trace_id).to_not eq(trace_id)
      expect(span.parent_id).to eq(0)
      expect(trace.sampling_priority).to_not be nil
      expect(trace.origin).to be nil
    end
  end

  context 'by default' do
    context 'and a request is received' do
      include_context 'an incoming HTTP request'

      context 'with distributed tracing headers' do
        include_context 'distributed tracing headers'
        it_behaves_like 'a Rack request with distributed tracing'

        context 'and request_queuing is enabled including the request time' do
          let(:rack_options) { super().merge(request_queuing: :include_request, web_service_name: web_service_name) }
          let(:web_service_name) { 'frontend_web_server' }

          before do
            header 'X-Request-Start', "t=#{Time.now.to_f}"
          end

          it 'contains a request_queuing span that belongs to the distributed trace' do
            is_expected.to be_ok

            expect(trace.sampling_priority).to eq(sampling_priority)

            expect(spans).to have(2).items

            server_queue_span = spans[0]
            rack_span = spans[1]

            expect(server_queue_span.name).to eq('http_server.queue')
            expect(server_queue_span.trace_id).to eq(trace_id)
            expect(server_queue_span.parent_id).to eq(parent_id)

            expect(rack_span.name).to eq('rack.request')
            expect(rack_span.trace_id).to eq(trace_id)
            expect(rack_span.parent_id).to eq(server_queue_span.span_id)
          end
        end

        context 'and request_queuing is enabled excluding the request time' do
          let(:rack_options) { super().merge(request_queuing: :exclude_request, web_service_name: web_service_name) }
          let(:web_service_name) { 'frontend_web_server' }

          before do
            header 'X-Request-Start', "t=#{Time.now.to_f}"
          end

          it 'contains request and request_queuing spans that belongs to the distributed trace' do
            is_expected.to be_ok

            expect(trace.sampling_priority).to eq(sampling_priority)

            expect(spans).to have(3).items

            server_request_span = spans[1]
            server_queue_span = spans[0]
            rack_span = spans[2]

            expect(server_request_span.name).to eq('http.proxy.request')
            expect(server_request_span.trace_id).to eq(trace_id)
            expect(server_request_span.parent_id).to eq(parent_id)

            expect(server_queue_span.name).to eq('http.proxy.queue')
            expect(server_queue_span.trace_id).to eq(trace_id)
            expect(server_queue_span.parent_id).to eq(server_request_span.span_id)

            expect(rack_span.name).to eq('rack.request')
            expect(rack_span.trace_id).to eq(trace_id)
            expect(rack_span.parent_id).to eq(server_request_span.span_id)
          end
        end
      end

      context 'without distributed tracing headers' do
        include_context 'no distributed tracing headers'
        it_behaves_like 'a Rack request without distributed tracing'
      end
    end
  end

  context 'when disabled' do
    let(:rack_options) { super().merge(distributed_tracing: false) }

    context 'and a request is received' do
      include_context 'an incoming HTTP request'

      context 'with distributed tracing headers' do
        include_context 'distributed tracing headers'
        it_behaves_like 'a Rack request without distributed tracing'
      end

      context 'without distributed tracing headers' do
        include_context 'no distributed tracing headers'
        it_behaves_like 'a Rack request without distributed tracing'
      end
    end
  end
end
