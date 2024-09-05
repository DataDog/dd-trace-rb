require 'spec_helper'

require 'datadog/core/telemetry/logger'

RSpec.describe Datadog::Core::Telemetry::Logger do
  describe '.report' do
    context 'when there is a telemetry component configured' do
      it do
        exception = StandardError.new
        telemetry = instance_double(Datadog::Core::Telemetry::Component)
        allow(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
        expect(telemetry).to receive(:report).with(exception, level: :error, description: 'Oops...')

        expect do
          described_class.report(exception, level: :error, description: 'Oops...')
        end.not_to raise_error
      end

      context 'when only given an exception' do
        it do
          exception = StandardError.new
          telemetry = instance_double(Datadog::Core::Telemetry::Component)
          allow(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
          expect(telemetry).to receive(:report).with(exception, level: :error, description: nil)

          expect do
            described_class.report(exception)
          end.not_to raise_error
        end
      end
    end

    context 'when there is no telemetry component configured' do
      it do
        exception = StandardError.new
        allow(Datadog.send(:components)).to receive(:telemetry).and_return(nil)

        expect do
          described_class.report(exception, level: :error, description: 'Oops...')
        end.not_to raise_error
      end
    end
  end

  describe '.error' do
    context 'when there is a telemetry component configured' do
      it do
        telemetry = instance_double(Datadog::Core::Telemetry::Component)
        allow(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
        expect(telemetry).to receive(:error).with('description')

        expect { described_class.error('description') }.not_to raise_error
      end
    end

    context 'when there is no telemetry component configured' do
      it do
        allow(Datadog.send(:components)).to receive(:telemetry).and_return(nil)

        expect { described_class.error('description') }.not_to raise_error
      end
    end
  end
end
