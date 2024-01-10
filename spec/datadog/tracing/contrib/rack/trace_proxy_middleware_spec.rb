require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/rack/trace_proxy_middleware'

RSpec.describe Datadog::Tracing::Contrib::Rack::TraceProxyMiddleware do
  describe '#call' do
    let(:service) { 'nginx' }

    context 'when given timestamp' do
      let(:timestamp) { Time.now.utc }

      context 'when request_queuing: true' do
        it 'behaves like request_queuing: :exclude_request' do
          env = double
          expect(Datadog::Tracing::Contrib::Rack::QueueTime).to receive(:get_request_start).with(env).and_return(timestamp)

          result = described_class.call(env, request_queuing: true, web_service_name: service) { :success }

          expect(result).to eq :success

          expect(spans).to have(2).items

          queue_span, request_span = spans

          expect(request_span).to be_root_span
          expect(request_span.name).to eq('http.proxy.request')
          expect(request_span.resource).to eq('http.proxy.request')
          expect(request_span.service).to eq(service)
          expect(request_span.start_time).to eq(timestamp)
          expect(request_span.get_tag('component')).to eq('http_proxy')
          expect(request_span.get_tag('operation')).to eq('request')
          expect(request_span.get_tag('span.kind')).to eq('proxy')

          expect(queue_span.parent_id).to eq(request_span.id)
          expect(queue_span.name).to eq('http.proxy.queue')
          expect(queue_span.resource).to eq('http.proxy.queue')
          expect(queue_span.service).to eq(service)
          expect(queue_span.start_time).to eq(timestamp)
          expect(queue_span.get_tag('component')).to eq('http_proxy')
          expect(queue_span.get_tag('operation')).to eq('queue')
          expect(queue_span.get_tag('span.kind')).to eq('proxy')
          expect(queue_span).to be_measured
        end
      end

      context 'when request_queuing: false' do
        it 'does not create spans' do
          env = double
          allow(Datadog::Tracing::Contrib::Rack::QueueTime).to receive(:get_request_start).with(env).and_return(timestamp)

          result = described_class.call(env, request_queuing: false, web_service_name: service) { :success }

          expect(result).to eq :success

          expect(spans).to have(0).items
        end
      end

      context 'when request_queuing: :exclude_request' do
        it 'creates 2 spans' do
          env = double
          expect(Datadog::Tracing::Contrib::Rack::QueueTime).to receive(:get_request_start).with(env).and_return(timestamp)

          result = described_class.call(env, request_queuing: :exclude_request, web_service_name: service) { :success }

          expect(result).to eq :success

          expect(spans).to have(2).items

          queue_span, request_span = spans

          expect(request_span).to be_root_span
          expect(request_span.name).to eq('http.proxy.request')
          expect(request_span.resource).to eq('http.proxy.request')
          expect(request_span.service).to eq(service)
          expect(request_span.start_time).to eq(timestamp)
          expect(request_span.get_tag('component')).to eq('http_proxy')
          expect(request_span.get_tag('operation')).to eq('request')
          expect(request_span.get_tag('span.kind')).to eq('proxy')

          expect(queue_span.parent_id).to eq(request_span.id)
          expect(queue_span.name).to eq('http.proxy.queue')
          expect(queue_span.resource).to eq('http.proxy.queue')
          expect(queue_span.service).to eq(service)
          expect(queue_span.start_time).to eq(timestamp)
          expect(queue_span.get_tag('component')).to eq('http_proxy')
          expect(queue_span.get_tag('operation')).to eq('queue')
          expect(queue_span.get_tag('span.kind')).to eq('proxy')
          expect(queue_span).to be_measured
        end
      end
    end

    context 'when given withouht timestamp' do
      let(:timestamp) { nil }

      context 'when request_queuing: true' do
        it 'does not create spans' do
          env = double
          expect(Datadog::Tracing::Contrib::Rack::QueueTime).to receive(:get_request_start).with(env).and_return(timestamp)

          result = described_class.call(env, request_queuing: true, web_service_name: service) { :success }

          expect(result).to eq :success

          expect(spans).to have(0).items
        end
      end

      context 'when request_queuing: false' do
        it 'does not create spans' do
          env = double
          allow(Datadog::Tracing::Contrib::Rack::QueueTime).to receive(:get_request_start).with(env).and_return(timestamp)

          result = described_class.call(env, request_queuing: false, web_service_name: service) { :success }

          expect(result).to eq :success

          expect(spans).to have(0).items
        end
      end

      context 'when request_queuing: :exclude_request' do
        it 'does not create spans' do
          env = double
          expect(Datadog::Tracing::Contrib::Rack::QueueTime).to receive(:get_request_start).with(env).and_return(timestamp)

          result = described_class.call(env, request_queuing: :exclude_request, web_service_name: service) { :success }

          expect(result).to eq :success

          expect(spans).to have(0).items
        end
      end
    end
  end
end
