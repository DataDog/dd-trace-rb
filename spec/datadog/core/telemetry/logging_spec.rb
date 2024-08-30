require 'spec_helper'

require 'datadog/core/telemetry/logging'
require 'datadog/core/telemetry/component'

RSpec.describe Datadog::Core::Telemetry::Logging do
  describe '.report' do
    context 'with named exception' do
      it 'sends a log event to via telemetry' do
        telemetry = instance_double(Datadog::Core::Telemetry::Component)
        allow(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
        expect(telemetry).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(
            logs: [{ message: 'RuntimeError', level: 'ERROR',
                     stack_trace: a_string_including('REDACTED') }]
          )
        end

        begin
          raise 'Invalid token: p@ssw0rd'
        rescue StandardError => e
          described_class.report(e, level: :error)
        end
      end

      context 'with description' do
        it 'sends a log event to via telemetry' do
          telemetry = instance_double(Datadog::Core::Telemetry::Component)
          allow(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
          expect(telemetry).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
            expect(event.payload).to include(
              logs: [{ message: 'RuntimeError:Must not contain PII', level: 'ERROR',
                       stack_trace: a_string_including('REDACTED') }]
            )
          end

          begin
            raise 'Invalid token: p@ssw0rd'
          rescue StandardError => e
            described_class.report(e, level: :error, description: 'Must not contain PII')
          end
        end
      end
    end

    context 'with anonymous exception' do
      it 'sends a log event to via telemetry' do
        telemetry = instance_double(Datadog::Core::Telemetry::Component)
        allow(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
        expect(telemetry).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(
            logs: [{ message: /#<Class:/, level: 'ERROR',
                     stack_trace: a_string_including('REDACTED') }]
          )
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
          expect(block.call).to match(/Attempting to send telemetry log when telemetry component is not ready/)
        end

        begin
          raise 'Invalid token: p@ssw0rd'
        rescue StandardError => e
          described_class.report(e, level: :error)
        end
      end
    end
  end

  describe '.error' do
    context 'with description' do
      it 'sends a log event to via telemetry' do
        telemetry = instance_double(Datadog::Core::Telemetry::Component)
        allow(Datadog.send(:components)).to receive(:telemetry).and_return(telemetry)
        expect(telemetry).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(logs: [{ message: 'Must not contain PII', level: 'ERROR' }])
        end

        described_class.error('Must not contain PII')
      end
    end

    context 'when telemetry component is not available' do
      it 'does not sends a log event to via telemetry' do
        logger = Logger.new($stdout)
        expect(Datadog.send(:components)).to receive(:telemetry).and_return(nil)
        expect(Datadog).to receive(:logger).and_return(logger)
        expect(logger).to receive(:debug).with(no_args) do |&block|
          expect(block.call).to match(/Attempting to send telemetry log when telemetry component is not ready/)
        end

        described_class.error('Must not contain PII')
      end
    end
  end
end

RSpec.describe Datadog::Core::Telemetry::Logging::DatadogStackTrace do
  describe '.from' do
    it do
      exception = StandardError.new('Yo!')

      result = described_class.from(exception)

      expect(result).to be_nil
    end

    it do
      exception = StandardError.new('Yo!')
      exception.set_backtrace([])

      result = described_class.from(exception)

      expect(result).to be_nil
    end

    it 'returns redacted stack trace' do
      begin
        raise 'Invalid token: p@ssw0rd'
      rescue StandardError => e
        result = described_class.from(e)
      end

      expect(result).to start_with('/spec/datadog/core/telemetry/logging_spec.rb')
      expect(result).to end_with('REDACTED')
    end
  end
end
