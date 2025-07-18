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
                     stack_trace: a_string_including("\n/spec/") }]
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
              logs: [{ message: 'RuntimeError: Must not contain PII', level: 'ERROR', count: 1,
                       stack_trace: a_string_including('REDACTED') }]
            )
            expect(event.payload).to include(
              logs: [{ message: 'RuntimeError: Must not contain PII', level: 'ERROR', count: 1,
                       stack_trace: a_string_including("\n/spec/") }]
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
            logs: [{ message: /#<Class:/, level: 'ERROR', count: 1,
                     stack_trace: a_string_including('REDACTED') }]
          )
          expect(event.payload).to include(
            logs: [{ message: /#<Class:/, level: 'ERROR', count: 1,
                     stack_trace: a_string_including("\n/spec/") }]
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

    context 'when pii_safe is true' do
      it 'sends a log event to via telemetry including the exception message' do
        expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.message).to eq('StandardError: (Test exception message without pii)')
        end

        component.report(
          StandardError.new('Test exception message without pii'),
          level: :error,
          pii_safe: true,
        )
      end

      context 'when a description is provided' do
        it 'sends a log event to via telemetry including the description' do
          expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
            expect(event.message).to eq('StandardError: Test description (Test exception message without pii)')
          end

          component.report(
            StandardError.new('Test exception message without pii'),
            description: 'Test description',
            level: :error,
            pii_safe: true,
          )
        end
      end
    end
  end

  describe '.error' do
    context 'with description' do
      it 'sends a log event to via telemetry' do
        expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(logs: [{ message: 'Must not contain PII', level: 'ERROR', count: 1 }])
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
