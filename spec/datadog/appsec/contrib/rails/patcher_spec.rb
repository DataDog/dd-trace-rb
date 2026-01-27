# frozen_string_literal: true

require 'active_support'
require 'datadog/appsec'

RSpec.describe Datadog::AppSec::Contrib::Rails::Patcher do
  describe '.patch' do
    before do
      allow(Datadog.logger).to receive(:error)
      allow(Datadog::AppSec).to receive(:telemetry).and_return(double(report: nil))

      described_class.patch
    end

    describe 'error handling in :after_routes_loaded load hook' do
      context 'when unexpected argument causes error' do
        it 'catches the error and logs it' do
          ActiveSupport.run_load_hooks(:after_routes_loaded, Class.new)

          expect(Datadog.logger).to have_received(:error).with(
            /Failed to get application routes/
          ).at_least(:once)
        end

        it 'reports the error to telemetry' do
          ActiveSupport.run_load_hooks(:after_routes_loaded, Class.new)

          expect(Datadog::AppSec.telemetry).to have_received(:report).with(
            an_instance_of(NoMethodError),
            description: 'Failed to get application routes'
          ).at_least(:once)
        end
      end
    end
  end
end
