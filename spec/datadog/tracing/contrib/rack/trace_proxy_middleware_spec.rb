require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/rack/trace_proxy_middleware'

RSpec.describe Datadog::Tracing::Contrib::Rack::TraceProxyMiddleware do
  describe '#call' do
    let(:service) { 'nginx' }
    let(:env) { {'HTTP_X_REQUEST_START' => timestamp.to_i * 1000} }

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

    context 'when x-dd-proxy header is present' do
      let(:env) do
        {
          'HTTP_X_DD_PROXY' => 'aws-apigateway',
          'HTTP_X_DD_PROXY_REQUEST_TIME_MS' => '1757000000000',
          'HTTP_X_DD_PROXY_PATH' => '/api/test',
          'HTTP_X_DD_PROXY_RESOURCE_PATH' => '/api/{proxy+}',
          'HTTP_X_DD_PROXY_HTTPMETHOD' => 'GET',
          'HTTP_X_DD_PROXY_DOMAIN_NAME' => 'example.execute-api.us-east-1.amazonaws.com',
          'HTTP_X_DD_PROXY_STAGE' => 'dev',
        }
      end

      context 'when proxy type is aws-apigateway' do
        before { described_class.call(env, request_queuing: false, web_service_name: service) { :success } }

        let(:inferred_span) { spans.first }

        it { expect(spans).to have(1).item }
        it { expect(inferred_span.name).to eq('aws.apigateway') }
        it { expect(inferred_span.type).to eq('web') }
        it { expect(inferred_span.service).to eq('example.execute-api.us-east-1.amazonaws.com') }
        it { expect(inferred_span.resource).to eq('GET /api/{proxy+}') }
        it { expect(inferred_span.start_time).to eq(Time.at(1757000000.0)) }
        it { expect(inferred_span.get_tag('component')).to eq('aws-apigateway') }
        it { expect(inferred_span.get_tag('span.kind')).to eq('server') }
        it { expect(inferred_span.get_tag('stage')).to eq('dev') }
        it { expect(inferred_span.get_tag('http.method')).to eq('GET') }
        it { expect(inferred_span.get_tag('http.url')).to eq('https://example.execute-api.us-east-1.amazonaws.com/api/test') }
        it { expect(inferred_span.get_tag('http.route')).to eq('/api/{proxy+}') }
        it { expect(inferred_span.get_metric('_dd.inferred_span')).to eq(1) }

        it 'returns the block result' do
          expect(described_class.call(env, request_queuing: false, web_service_name: service) { :success }).to eq(:success)
        end
      end

      context 'when proxy type is aws-httpapi' do
        let(:env) do
          {
            'HTTP_X_DD_PROXY' => 'aws-httpapi',
            'HTTP_X_DD_PROXY_REQUEST_TIME_MS' => '1757000000000',
            'HTTP_X_DD_PROXY_PATH' => '/api/test',
            'HTTP_X_DD_PROXY_RESOURCE_PATH' => '/api/{proxy+}',
            'HTTP_X_DD_PROXY_HTTPMETHOD' => 'GET',
            'HTTP_X_DD_PROXY_DOMAIN_NAME' => 'example.execute-api.us-east-1.amazonaws.com',
            'HTTP_X_DD_PROXY_STAGE' => 'dev',
          }
        end

        before { described_class.call(env, request_queuing: false, web_service_name: service) { :success } }

        let(:inferred_span) { spans.first }

        it { expect(inferred_span.name).to eq('aws.httpapi') }
        it { expect(inferred_span.get_tag('component')).to eq('aws-httpapi') }
      end

      context 'when x-dd-proxy-resource-path is absent' do
        let(:env) do
          {
            'HTTP_X_DD_PROXY' => 'aws-apigateway',
            'HTTP_X_DD_PROXY_REQUEST_TIME_MS' => '1757000000000',
            'HTTP_X_DD_PROXY_PATH' => '/api/test',
            'HTTP_X_DD_PROXY_HTTPMETHOD' => 'GET',
            'HTTP_X_DD_PROXY_DOMAIN_NAME' => 'example.execute-api.us-east-1.amazonaws.com',
            'HTTP_X_DD_PROXY_STAGE' => 'dev',
          }
        end

        before { described_class.call(env, request_queuing: false, web_service_name: service) { :success } }

        let(:inferred_span) { spans.first }

        it { expect(inferred_span.resource).to eq('GET /api/test') }
        it { expect(inferred_span.get_tag('http.route')).to be_nil }
      end

      context 'when optional headers are present' do
        let(:env) do
          {
            'HTTP_X_DD_PROXY' => 'aws-apigateway',
            'HTTP_X_DD_PROXY_REQUEST_TIME_MS' => '1757000000000',
            'HTTP_X_DD_PROXY_PATH' => '/api/test',
            'HTTP_X_DD_PROXY_RESOURCE_PATH' => '/api/{proxy+}',
            'HTTP_X_DD_PROXY_HTTPMETHOD' => 'GET',
            'HTTP_X_DD_PROXY_DOMAIN_NAME' => 'example.execute-api.us-east-1.amazonaws.com',
            'HTTP_X_DD_PROXY_STAGE' => 'dev',
            'HTTP_X_DD_PROXY_ACCOUNT_ID' => '123456789',
            'HTTP_X_DD_PROXY_API_ID' => 'abc123',
            'HTTP_X_DD_PROXY_REGION' => 'us-east-1',
            'HTTP_X_DD_PROXY_USER' => 'test-user',
          }
        end

        before { described_class.call(env, request_queuing: false, web_service_name: service) { :success } }

        let(:inferred_span) { spans.first }

        it { expect(inferred_span.get_tag('account_id')).to eq('123456789') }
        it { expect(inferred_span.get_tag('apiid')).to eq('abc123') }
        it { expect(inferred_span.get_tag('region')).to eq('us-east-1') }
        it { expect(inferred_span.get_tag('dd_resource_key')).to eq('arn:aws:apigateway:us-east-1::/restapis/abc123') }
        it { expect(inferred_span.get_tag('aws_user')).to eq('test-user') }

        context 'when proxy type is aws-httpapi' do
          let(:env) do
            {
              'HTTP_X_DD_PROXY' => 'aws-httpapi',
              'HTTP_X_DD_PROXY_REQUEST_TIME_MS' => '1757000000000',
              'HTTP_X_DD_PROXY_PATH' => '/api/test',
              'HTTP_X_DD_PROXY_RESOURCE_PATH' => '/api/{proxy+}',
              'HTTP_X_DD_PROXY_HTTPMETHOD' => 'GET',
              'HTTP_X_DD_PROXY_DOMAIN_NAME' => 'example.execute-api.us-east-1.amazonaws.com',
              'HTTP_X_DD_PROXY_STAGE' => 'dev',
              'HTTP_X_DD_PROXY_ACCOUNT_ID' => '123456789',
              'HTTP_X_DD_PROXY_API_ID' => 'abc123',
              'HTTP_X_DD_PROXY_REGION' => 'us-east-1',
              'HTTP_X_DD_PROXY_USER' => 'test-user',
            }
          end

          before { described_class.call(env, request_queuing: false, web_service_name: service) { :success } }

          let(:inferred_span) { spans.first }

          it { expect(inferred_span.get_tag('dd_resource_key')).to eq('arn:aws:apigateway:us-east-1::/apis/abc123') }
        end
      end

      context 'when response status is 500' do
        before do
          described_class.call(env, request_queuing: false, web_service_name: service) do
            rack_span = Datadog::Tracing.trace('rack.request')
            rack_span.set_tag('http.status_code', '500')
            env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN] = rack_span
            rack_span.finish
          end
        end

        let(:inferred_span) { spans.find { |s| s.name == 'aws.apigateway' } }

        it { expect(inferred_span.get_tag('http.status_code')).to eq('500') }
        it { expect(inferred_span.status).to eq(1) }
      end

      context 'when response status is 200' do
        before do
          described_class.call(env, request_queuing: false, web_service_name: service) do
            rack_span = Datadog::Tracing.trace('rack.request')
            rack_span.set_tag('http.status_code', '200')
            env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN] = rack_span
            rack_span.finish
          end
        end

        let(:inferred_span) { spans.find { |s| s.name == 'aws.apigateway' } }

        it { expect(inferred_span.get_tag('http.status_code')).to eq('200') }
        it { expect(inferred_span.status).to eq(0) }
      end

      context 'when AppSec tags are present on rack.request span' do
        before do
          described_class.call(env, request_queuing: false, web_service_name: service) do
            rack_span = Datadog::Tracing.trace('rack.request')
            rack_span.set_metric('_dd.appsec.enabled', 1.0)
            rack_span.set_tag('_dd.appsec.json', '{"triggers":[]}')
            rack_span.set_tag('http.status_code', '200')
            env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN] = rack_span
            rack_span.finish
          end
        end

        let(:inferred_span) { spans.find { |s| s.name == 'aws.apigateway' } }

        it { expect(inferred_span.get_metric('_dd.appsec.enabled')).to eq(1.0) }
        it { expect(inferred_span.get_tag('_dd.appsec.json')).to eq('{"triggers":[]}') }
      end

      it 'finishes the span even when an exception is raised' do
        expect do
          described_class.call(env, request_queuing: false, web_service_name: service) { raise 'error' }
        end.to raise_error('error')

        expect(spans).to have(1).item
        expect(spans.first).to be_finished
      end

      context 'when request_queuing is true and x-request-start is also present' do
        let(:env) do
          {
            'HTTP_X_DD_PROXY' => 'aws-apigateway',
            'HTTP_X_DD_PROXY_REQUEST_TIME_MS' => '1757000000000',
            'HTTP_X_DD_PROXY_PATH' => '/api/test',
            'HTTP_X_DD_PROXY_RESOURCE_PATH' => '/api/{proxy+}',
            'HTTP_X_DD_PROXY_HTTPMETHOD' => 'GET',
            'HTTP_X_DD_PROXY_DOMAIN_NAME' => 'example.execute-api.us-east-1.amazonaws.com',
            'HTTP_X_DD_PROXY_STAGE' => 'dev',
            'HTTP_X_REQUEST_START' => '1757000000000',
          }
        end

        before { described_class.call(env, request_queuing: true, web_service_name: service) { :success } }

        it 'creates inferred proxy span instead of request_queuing spans' do
          expect(spans.any? { |s| s.name == 'aws.apigateway' }).to be(true)
          expect(spans.none? { |s| s.name == 'http.proxy.request' }).to be(true)
        end
      end
    end
  end
end
