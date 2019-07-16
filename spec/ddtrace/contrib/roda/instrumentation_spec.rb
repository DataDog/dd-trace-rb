require 'spec_helper'
require 'roda'
require 'ddtrace'
require 'ddtrace/contrib/roda/instrumentation'
require 'ddtrace/contrib/roda/ext'

RSpec.describe Datadog::Contrib::Roda::Instrumentation do
  describe 'when implemented in Roda' do
    
    let(:configuration_options) { { tracer: tracer } }
    let(:tracer) { get_test_tracer }
    let(:spans) { tracer.writer.spans }
    let(:span) { spans.first }

    before(:each) do
      Datadog.configure do |c|
        c.use :roda, configuration_options
      end
    end
  
    after(:each) do
      Datadog.registry[:roda].reset_configuration!
    end

    describe '#datadog_pin' do
      let(:test_class) { Class.new(Roda) }
      let(:roda) { test_class.new(env) }
      let(:env) { {:REQUEST_METHOD =>'GET'} }
      subject(:datadog_pin) { roda.datadog_pin }

      context 'when roda is configured' do

        context 'with default settings' do
          
          it 'enables the tracer' do
            expect(datadog_pin.tracer).to be(Datadog.configuration[:roda][:tracer])
            expect(datadog_pin.tracer.enabled).to eq(true)
          end

          it 'has a web app type' do
            expect(datadog_pin.app_type).to eq(Datadog::Ext::AppTypes::WEB)
          end

          it 'has a default name' do
            expect(datadog_pin.app).to eq(Datadog::Contrib::Roda::Ext::APP)
            expect(datadog_pin.service).to eq(Datadog::Contrib::Roda::Ext::SERVICE_NAME)
            expect(datadog_pin.service_name).to eq(Datadog::Contrib::Roda::Ext::SERVICE_NAME)
          end

          context 'with a custom service name' do
            let(:custom_service_name) {"custom service name"}
            let(:configuration_options) { { tracer: tracer, service_name: custom_service_name } }

            it 'sets a custom service name' do
              expect(datadog_pin.app).to eq(Datadog::Contrib::Roda::Ext::APP)
              expect(datadog_pin.service).to eq(custom_service_name)
              expect(datadog_pin.service_name).to eq(custom_service_name)
            end
          end
        end
      end
    end

    describe '#call' do
      subject(:call) { roda.call }
      let(:roda) { test_class.new }
      let(:test_class) do
        Class.new do
          prepend Datadog::Contrib::Roda::Instrumentation
        end
      end

      shared_context 'stubbed request' do
        let(:env) { instance_double(Hash) }
        let(:response_method) { :get }
        let(:path) { '/' }

        let(:request) do
          instance_double(
            ::Rack::Request,
            request_method: response_method,
            path: path
           )
        end

        before do
          e = env
          test_class.send(:define_method, :env) do |*args|
              e
          end

          expect(::Rack::Request).to receive(:new)
           .with(env)
           .and_return(request)
        end
      end

      shared_context 'stubbed response' do
        let(:spy) { instance_double(Roda) }
        let(:response) {[response_code, instance_double(Hash), double('body')]}
        let(:response_code) { 200 }
        let(:response_headers) { double('body') }

        before do
          s = spy
          test_class.send(:define_method, :call) do |*args|
              s.call
          end
          expect(spy).to receive(:call)
           .and_return(response)
        end
      end
      
      context 'when the response code is' do
        include_context 'stubbed request'
        include_context 'stubbed response' do
          let(:env) { {'HTTP_X_DATADOG_TRACE_ID' => '0'} }
        end
        
        context '200' do
          let(:response_code) { 200 }
        
          it do
            call
            expect(spans).to have(1).items
            expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(nil)
            expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
            expect(span.status).to eq(0)
            expect(span.resource).to eq("GET")
            expect(span.name).to eq("roda.request")
            expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
            expect(span.parent).to be nil
          end
        end

        context '404' do
          let(:response_code) { 404 }
          let(:path) { '/unsuccessful_endpoint' }
          
          it do
            call
            expect(spans).to have(1).items
            expect(span.parent).to be nil
            expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(nil)
            expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
            expect(span.resource).to eq("GET")
            expect(span.name).to eq("roda.request")
            expect(span.status).to eq(0)
            expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/unsuccessful_endpoint')
          end
        end
        
        context '500' do
          let(:response_code) { 500 }

          it do
            call
            expect(spans).to have(1).items
            expect(span.parent).to be nil
            expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(nil)
            expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
            expect(span.resource).to eq("GET")
            expect(span.name).to eq("roda.request")
            expect(span.status).to eq(1)
            expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
          end
        end
      end


      context 'when the verb is' do

      end

      context 'when the path is' do

      end

      context 'when distributed tracing' do
        include_context 'stubbed request'
        
        let(:sampling_priority) {Datadog::Ext::Priority::USER_KEEP.to_s}
        
        context 'is enabled' do
          context 'without origin' do
            include_context 'stubbed response' do
              let(:env) do
                {
                  'HTTP_X_DATADOG_TRACE_ID' => '40000',
                  'HTTP_X_DATADOG_PARENT_ID' => '50000',
                  'HTTP_X_DATADOG_SAMPLING_PRIORITY' => sampling_priority,
                }
              end
            end

            it do
              call
              expect(spans).to have(1).items
              expect(span.trace_id).to eq(40000)
              expect(span.parent_id).to eq(50000)
              expect(Datadog.configuration[:roda][:distributed_tracing]).to be(true)
              expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(sampling_priority.to_f)
              expect(span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)).to be nil
            end
          end

          context 'with origin' do
            include_context 'stubbed response' do
              let(:env) do
              {
                'HTTP_X_DATADOG_TRACE_ID' => '10000',
                'HTTP_X_DATADOG_PARENT_ID' => '20000',
                'HTTP_X_DATADOG_SAMPLING_PRIORITY' => sampling_priority,
                'HTTP_X_DATADOG_ORIGIN' => 'synthetics'
              }
              end
            end

            it do
              call
              expect(spans).to have(1).items
              expect(span.trace_id).to eq(10000)
              expect(span.parent_id).to eq(20000)
              expect(Datadog.configuration[:roda][:distributed_tracing]).to be(true)
              expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(sampling_priority.to_f)
              expect(span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)).to eq('synthetics')
            end
          end
        end

        context 'is disabled' do
          let(:configuration_options) { { tracer: tracer, distributed_tracing: false } }
          include_context 'stubbed response' do
            let(:env) do
                  {
                    'HTTP_X_DATADOG_TRACE_ID' => '40000',
                    'HTTP_X_DATADOG_PARENT_ID' => '50000',
                    'HTTP_X_DATADOG_SAMPLING_PRIORITY' => sampling_priority,
                  }
            end
          end
          
          it 'does not take on the passed in trace context' do
            call
            expect(Datadog.configuration[:roda][:distributed_tracing]).to be(false)
            expect(spans).to have(1).items
            expect(span.trace_id).to_not eq(40000)
            expect(span.parent_id).to_not eq(50000)
          end
        end
      end      
    end
  end
end