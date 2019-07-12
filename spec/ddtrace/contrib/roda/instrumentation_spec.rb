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

        context 'tracer is enabled' do
          before {Datadog.configure {|c| c.use :roda}}
          it 'enables the tracer' do
            expect(datadog_pin.tracer.enabled).to eq(true)
          end
          it 'has a web app type' do
            expect(datadog_pin.app_type).to eq(Datadog::Ext::AppTypes::WEB)
          end
        end

        context 'with a custom service name' do
          let(:custom_service_name) {"custom service name"}

          before {Datadog.configure {|c| c.use :roda, service_name: custom_service_name}}
          it 'sets a custom service name' do
            expect(datadog_pin.service_name).to eq(custom_service_name)
          end
        end

        context 'without a service name' do
          before {Datadog.configure {|c| c.use :roda}}
          it 'sets a default' do
            expect(datadog_pin.service_name).to eq(Datadog::Contrib::Roda::Ext::SERVICE_NAME)
          end
        end
      end
    end


    describe '#call' do
      subject(:test_class) do
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
      let(:env) {instance_double(Hash)}
      let(:rack_request) do
          instance_double(
            ::Rack::Request,
            request_method: :get,
            path: '/'
            )
      end
    
      subject(:roda) {test_class.new}
        before do
          allow(spy).to receive(:call)
           .and_return(response)
          allow(::Rack::Request).to receive(:new)
           .with(env)
           .and_return(rack_request)
        end

      context 'when it receives a 200' do
        let(:response) {[200,instance_double(Hash), double('body')]}

        it do
          roda.call
          expect(spy).to have_received(:call)
        end
      end
      context 'when it receives a 500' do
        let(:response) {[500,instance_double(Hash), double('body')]}

        it do
          roda.call
          expect(spy).to have_received(:call)
        end
      end
    end
  end
end