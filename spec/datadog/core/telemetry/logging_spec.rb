require 'spec_helper'

require 'datadog/core/telemetry/logging'

RSpec.describe Datadog::Core::Telemetry::Logging do
  let(:dummy_class) do
    Class.new do
      include Datadog::Core::Telemetry::Logging
      def log!(_event)
        :logs!
      end
    end
  end

  let(:component) { dummy_class.new }

  describe '.report' do
    context 'with named exception' do
      it 'sends a log event to via telemetry' do
        expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(
            logs: [{ message: 'RuntimeError', level: 'ERROR', count: 1,
                     stack_trace: a_string_including('REDACTED') }]
          )
          expect(event.payload).to include(
            logs: [{ message: 'RuntimeError', level: 'ERROR', count: 1,
                     stack_trace: a_string_including(',/spec/') }]
          )
        end

        begin
          raise 'Invalid token: p@ssw0rd'
        rescue StandardError => e
          component.report(e, level: :error)
        end
      end

      context 'with description' do
        it 'sends a log event to via telemetry' do
          expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
            expect(event.payload).to include(
              logs: [{ message: 'RuntimeError:Must not contain PII', level: 'ERROR', count: 1,
                       stack_trace: a_string_including('REDACTED') }]
            )
            expect(event.payload).to include(
              logs: [{ message: 'RuntimeError:Must not contain PII', level: 'ERROR', count: 1,
                       stack_trace: a_string_including(',/spec/') }]
            )
          end

          begin
            raise 'Invalid token: p@ssw0rd'
          rescue StandardError => e
            component.report(e, level: :error, description: 'Must not contain PII')
          end
        end
      end
    end

    context 'with anonymous exception' do
      it 'sends a log event to via telemetry' do
        expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(
            logs: [{ message: /#<Class:/, level: 'ERROR',
                     stack_trace: a_string_including('REDACTED') }]
          )
          expect(event.payload).to include(
            logs: [{ message: /#<Class:/, level: 'ERROR',
                     stack_trace: a_string_including(',/spec/') }]
          )
        end

        customer_exception = Class.new(StandardError)

        begin
          raise customer_exception, 'Invalid token: p@ssw0rd'
        rescue StandardError => e
          component.report(e, level: :error)
        end
      end
    end
  end

  describe '.error' do
    context 'with description' do
      it 'sends a log event to via telemetry' do
        expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(logs: [{ message: 'Must not contain PII', level: 'ERROR' }])
        end

        component.error('Must not contain PII')
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
