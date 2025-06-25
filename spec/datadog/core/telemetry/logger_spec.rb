require 'spec_helper'

require 'datadog/core/telemetry/logger'

RSpec.describe Datadog::Core::Telemetry::Logger do
  let(:exception) { StandardError.new('Exception message') }

  before do
    expect(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
  end

  describe '.report' do
    context 'when there is a telemetry component configured' do
      let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

      it do
        expect(Datadog.logger).not_to receive(:warn)
        expect(telemetry).to receive(:report).with(exception, level: :error, description: 'Oops...', pii_safe: false)

        described_class.report(exception, level: :error, description: 'Oops...')
      end

      context 'when only given an exception' do
        it do
          expect(Datadog.logger).not_to receive(:warn)
          expect(telemetry).to receive(:report).with(exception, level: :error, description: nil, pii_safe: false)

          described_class.report(exception)
        end
      end

      context 'when pii_safe is true' do
        it do
          expect(Datadog.logger).not_to receive(:warn)
          expect(telemetry).to receive(:report).with(exception, level: :error, description: nil, pii_safe: true)

          described_class.report(exception, pii_safe: true)
        end
      end
    end

    context 'when there is no telemetry component configured' do
      let(:telemetry) { nil }

      it do
        expect(Datadog.logger).to receive(:warn).with(/Failed to send telemetry/)

        described_class.report(exception, level: :error, description: 'Oops...')
      end
    end
  end

  describe '.error' do
    context 'when there is a telemetry component configured' do
      let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

      it do
        expect(Datadog.logger).not_to receive(:warn)
        expect(telemetry).to receive(:error).with('description')

        described_class.error('description')
      end
    end

    context 'when there is no telemetry component configured' do
      let(:telemetry) { nil }

      it do
        expect(Datadog.logger).to receive(:warn).with(/Failed to send telemetry/)

        described_class.error('description')
      end
    end
  end
end
