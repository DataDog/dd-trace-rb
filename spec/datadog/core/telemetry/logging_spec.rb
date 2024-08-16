require 'spec_helper'

require 'datadog/core/telemetry/logging'

RSpec.describe Datadog::Core::Telemetry::Logging do
  describe '.report' do
    context 'with named exception' do
      it 'sends a log event to via telemetry' do
        telemetry = double('telemetry')
        allow(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
        expect(telemetry).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(message: 'RuntimeError', level: 'ERROR')
        end

        begin
          raise 'Invalid token: p@ssw0rd'
        rescue StandardError => e
          described_class.report(e, level: :error)
        end
      end
    end

    context 'with anonymous exception' do
      it 'sends a log event to via telemetry' do
        telemetry = double('telemetry')
        allow(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
        expect(telemetry).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(message: /#<Class:/, level: 'ERROR')
        end

        customer_exception = Class.new(StandardError)

        begin
          raise customer_exception, 'Invalid token: p@ssw0rd'
        rescue StandardError => e
          described_class.report(e, level: :error)
        end
      end
    end

    context 'when telemetry component is not available' do
      it 'does not sends a log event to via telemetry' do
        logger = Logger.new($stdout)
        expect(Datadog.send(:components)).to receive(:telemetry).and_return(nil)
        expect(Datadog).to receive(:logger).and_return(logger)
        expect(logger).to receive(:debug).with(no_args) do |&block|
          expect(block.call).to match /Attempting to send telemetry log when telemetry component is not ready/
        end

        begin
          raise 'Invalid token: p@ssw0rd'
        rescue StandardError => e
          described_class.report(e, level: :error)
        end
      end
    end
  end
end
