require 'spec_helper'
require 'rack/test'

require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'

RSpec.describe 'Rack integration distributed tracing' do
  include Rack::Test::Methods

  let(:tracer) { Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:rack_options) { { tracer: tracer } }

  let(:spans) { tracer.writer.spans }
  let(:span) { spans.first }

  before(:each) do
    Datadog.configure do |c|
      c.use :rack, rack_options
    end
  end

  after(:each) { Datadog.registry[:rack].reset_configuration! }

  shared_context 'an incoming HTTP request' do
    subject(:response) { get '/' }

    let(:app) do
      Rack::Builder.new do
        use Datadog::Contrib::Rack::TraceMiddleware

        map '/' do
          run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, 'OK'] })
        end
      end.to_app
    end
  end

  shared_context 'distributed tracing headers' do
    let(:trace_id) { 8694058539399423136 }
    let(:parent_id) { 3605612475141592985 }
    let(:sampling_priority) { Datadog::Ext::Priority::AUTO_KEEP }

    before(:each) do
      header Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID, trace_id
      header Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID, parent_id
      header Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY, sampling_priority
    end
  end

  shared_context 'no distributed tracing headers' do
    let(:trace_id) { nil }
    let(:parent_id) { nil }
    let(:sampling_priority) { nil }
  end

  shared_examples_for 'a Rack request with distributed tracing' do
    it 'produces a distributed Rack trace' do
      is_expected.to be_ok
      expect(span).to_not be nil
      expect(span.name).to eq('rack.request')
      expect(span.trace_id).to eq(trace_id)
      expect(span.parent_id).to eq(parent_id)
      expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(sampling_priority)
    end
  end

  shared_examples_for 'a Rack request without distributed tracing' do
    it 'produces a non-distributed Rack trace' do
      is_expected.to be_ok
      expect(span).to_not be nil
      expect(span.name).to eq('rack.request')
      expect(span.trace_id).to_not eq(trace_id)
      expect(span.parent_id).to eq(0)
      expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to be nil
    end
  end

  context 'when enabled' do
    let(:rack_options) { super().merge(distributed_tracing: true) }

    context 'and a request is received' do
      include_context 'an incoming HTTP request'

      context 'with distributed tracing headers' do
        include_context 'distributed tracing headers'
        it_behaves_like 'a Rack request with distributed tracing'
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
