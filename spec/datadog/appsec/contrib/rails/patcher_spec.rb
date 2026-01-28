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
      allow(telemetry).to receive(:report)

      described_class.patch
    end

    context ':after_routes_loaded hook' do
      context 'when error occurs while getting application routes' do
        before do
          allow(::Rails).to receive(:application).and_raise(StandardError)
        end

        it 'logs the error and reports it via telemetry' do
          ActiveSupport.run_load_hooks(:after_routes_loaded)

          expect(Datadog.logger).to have_received(:error).with(
            /Failed to get application routes/
          ).once

          expect(Datadog::AppSec.telemetry).to have_received(:report).with(
            an_instance_of(StandardError),
            description: 'Failed to get application routes'
          ).once
        end
      end
    end
  end
end
