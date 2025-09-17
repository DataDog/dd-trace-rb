require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/rack/trace_proxy_middleware'

RSpec.describe Datadog::Tracing::Contrib::Rack::TraceProxyMiddleware do
  describe '#call' do
    let(:service) { 'nginx' }
    let(:env) { { 'HTTP_X_REQUEST_START' => timestamp.to_i * 1000 } }

    context 'when given timestamp' do
      let(:timestamp) { Time.at(1757000000) }

      context 'when request_queuing: true' do
        it 'behaves like request_queuing: :exclude_request' do
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

        context 'when the request fails' do
          it 'finishes the spans even if an exception is raised' do
            expect do
              described_class.call(env, request_queuing: true, web_service_name: service) { raise 'error' }
            end.to raise_error('error')

            expect(spans).to have(2).items
            queue_span, request_span = spans
            expect(request_span).to be_root_span
            expect(queue_span.parent_id).to eq(request_span.id)
            expect(request_span).to be_finished
            expect(queue_span).to be_finished
          end
        end
      end

      context 'when request_queuing: false' do
        it 'does not create spans' do
          result = described_class.call(env, request_queuing: false, web_service_name: service) { :success }

          expect(result).to eq :success

          expect(spans).to have(0).items
        end
      end
    end

    context 'when given without timestamp' do
      let(:timestamp) { nil }

      context 'when request_queuing: true' do
        it 'does not create spans' do
          result = described_class.call(env, request_queuing: true, web_service_name: service) { :success }

          expect(result).to eq :success

          expect(spans).to have(0).items
        end
      end

      context 'when request_queuing: false' do
        it 'does not create spans' do
          result = described_class.call(env, request_queuing: false, web_service_name: service) { :success }

          expect(result).to eq :success

          expect(spans).to have(0).items
        end
      end
    end
  end
end
