# frozen_string_literal: true

require 'datadog/tracing/contrib/rails/rails_helper'
require 'datadog/appsec'

RSpec.describe Datadog::AppSec::Contrib::Rails::Patcher do
  describe '.patch' do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
    let(:logger) { instance_double(Datadog::Core::Logger) }

    before do
      allow(Datadog).to receive(:logger).and_return(logger)
      allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)

      allow(logger).to receive(:error)
      allow(logger).to receive(:debug)
      allow(logger).to receive(:debug?).and_return(false)
      allow(telemetry).to receive(:report)

      ActiveSupport.instance_variable_get(:@load_hooks).delete(:after_routes_loaded)
      ActiveSupport.instance_variable_get(:@loaded).delete(:action_controller)
    end

    context 'when called twice via instrument' do
      let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }
      let(:middlewares) { gateway.instance_variable_get(:@middlewares) }

      before do
        @original_patched = described_class.instance_variable_get(:@patched)
        described_class.instance_variable_set(:@patched, false)
        allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)

        Datadog.configure do |c|
          c.appsec.enabled = true
        end
      end

      after do
        described_class.instance_variable_set(:@patched, @original_patched)
        Datadog.configuration.reset!
      end

      it 'does not register gateway watchers twice' do
        Datadog.configuration.appsec.instrument :rails

        expect { Datadog.configuration.appsec.instrument :rails }.not_to change {
          middlewares.transform_values(&:size)
        }
      end
    end

    context ':after_routes_loaded hook' do
      context 'when error occurs while getting application routes' do
        before do
          described_class.patch
          allow(::Rails).to receive(:application).and_raise(StandardError)
        end

        it 'logs the error and reports it via telemetry' do
          ActiveSupport.run_load_hooks(:after_routes_loaded)

          expect(Datadog.logger).to have_received(:error).with(
            /Failed to get application routes/
          )

          expect(Datadog::AppSec.telemetry).to have_received(:report).with(
            an_instance_of(StandardError),
            description: 'Failed to get application routes'
          )
        end
      end
    end
  end
end
