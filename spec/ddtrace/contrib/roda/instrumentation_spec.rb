require 'spec_helper'
require 'roda'
require 'ddtrace'
require 'ddtrace/contrib/roda/instrumentation'
require 'ddtrace/contrib/roda/ext'

RSpec.describe Datadog::Contrib::Roda::Instrumentation do
  describe 'when implemented in Roda' do
    let(:test_class) {Class.new(Roda)}
    let(:env) {{:REQUEST_METHOD =>'GET'}}
    let(:roda) {test_class.new(env)}

    after(:each) do
      Datadog.registry[:roda].reset_configuration!
    end

    describe '#datadog_pin' do
      subject(:datadog_pin) {roda.datadog_pin}

      context 'when roda is configured' do

        context 'with default settings' do
          before { Datadog.configure {|c| c.use :roda } }
          
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

            before {Datadog.configure {|c| c.use :roda, service_name: custom_service_name}}
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
      let(:test_class) do
        s = spy
        e = env
        Class.new do
          prepend Datadog::Contrib::Roda::Instrumentation
        end
        .tap do |c|
          c.send(:define_method, :call) do |*args|
            s.call
          end
          c.send(:define_method, :env) do 
            e
          end          
        end

      end

      let(:spy) {instance_double(Roda)}
      let(:env) {{'HTTP_X_DATADOG_TRACE_ID' => '30000'}}
      # let(:env) {instance_double(Hash)}
      
      let(:rack_request) do
          instance_double(
            ::Rack::Request,
            request_method: :get,
            path: '/'
            )
      end

      let(:configuration_options) { { tracer: tracer } }
      let(:tracer) { get_test_tracer }
      let(:spans) { tracer.writer.spans }
      let(:span) { spans.first }
    
      let(:roda) {test_class.new}
        before do
          allow(spy).to receive(:call)
           .and_return(response)
          allow(::Rack::Request).to receive(:new)
           .with(env)
           .and_return(rack_request)
        end

      before(:each) do
        Datadog.configure do |c|
          c.use :roda, configuration_options
        end
      end

      context 'when it receives a successful request' do
        let(:response) {[200, instance_double(Hash), double('body')]}

        it do
          call
          expect(spy).to have_received(:call)
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

        context 'distributed tracing' do
          let(:sampling_priority) {Datadog::Ext::Priority::USER_KEEP.to_s}
          context 'with origin' do
            let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '10000',
              'HTTP_X_DATADOG_PARENT_ID' => '20000',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => sampling_priority,
              'HTTP_X_DATADOG_ORIGIN' => 'synthetics'
            }
            end

            it 'passes in headers and sets the context' do
              call
              expect(spans).to have(1).items
              expect(span.trace_id).to eq(10000)
              expect(span.parent_id).to eq(20000)
              expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(sampling_priority.to_f)
              expect(span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)).to eq('synthetics')

            end
          end

          context 'without origin' do
            let(:sampling_priority) {Datadog::Ext::Priority::USER_KEEP.to_s}
            let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '10000',
              'HTTP_X_DATADOG_PARENT_ID' => '20000',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => sampling_priority,
            }
            end

            it 'passes in headers' do
              call
              expect(spans).to have(1).items
              expect(span.trace_id).to eq(10000)
              expect(span.parent_id).to eq(20000)
              expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(sampling_priority.to_f)
              expect(span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)).to be nil
            end
          end

        end
      end
      context 'when it receives a server error' do
        let(:response) {[500,instance_double(Hash), double('body')]}

        it do
          roda.call
          expect(spy).to have_received(:call)
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
  end
end