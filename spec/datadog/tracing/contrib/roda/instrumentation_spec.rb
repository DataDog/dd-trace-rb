# typed: false

require_relative './shared_examples'
require 'roda'
require 'datadog'
require 'datadog/tracing/contrib/roda/instrumentation'
require 'datadog/tracing/contrib/roda/ext'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/support/tracer_helpers'

RSpec.describe Datadog::Tracing::Contrib::Roda::Instrumentation do
  describe 'when implemented in Roda' do
    let(:configuration_options) { {} }

    before do
      Datadog.configure do |c|
        c.tracing.instrument :roda, configuration_options
      end
    end

    after do
      Datadog.registry[:roda].reset_configuration!
    end

    describe 'When using automatic instrumentation' do
      let(:env) { { REQUEST_METHOD: 'GET' } }
      context 'configuring roda' do
        context 'with default settings' do
          it 'enables the tracer' do
            expect(Datadog.configuration.tracing.enabled).to eq(true)
          end

          it 'does not have a default service name (left up to global configuration)' do
            expect(Datadog.configuration.tracing[:roda].service_name).to eq(nil)
            expect(Datadog.configuration.service).to eq('rspec')
          end

          context 'with a custom service name' do
            let(:custom_service_name) { 'custom_service_name' }
            let(:configuration_options) { { service_name: custom_service_name } }

            it 'sets a custom service name' do
              expect(Datadog.configuration.service).to eq('rspec')
              expect(Datadog.configuration.tracing[:roda].service_name).to eq(custom_service_name)
            end
          end
        end
      end
    end

    describe 'when application calls on the instrumented method' do
      context 'using #call' do
        it_behaves_like 'shared examples for roda', :call
      end

      context 'using #_roda_handle_main_route' do
        it_behaves_like 'shared examples for roda', :_roda_handle_main_route
      end
    end
  end
end
