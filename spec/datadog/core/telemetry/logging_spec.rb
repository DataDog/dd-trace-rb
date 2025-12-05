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
            logs: [{message: 'RuntimeError', level: 'ERROR', count: 1,
                    stack_trace: a_string_including('REDACTED')}]
          )
          expect(event.payload).to include(
            logs: [{message: 'RuntimeError', level: 'ERROR', count: 1,
                    stack_trace: a_string_including("\n/spec/")}]
          )
          expect(event.payload[:logs].map { |log| log[:message] }).not_to include('p@ssw0rd')
        end

        begin
          raise 'Invalid token: p@ssw0rd'
        rescue => e
          component.report(e, level: :error)
        end
      end

      context 'with description' do
        it 'sends a log event to via telemetry' do
          expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
            expect(event.payload).to include(
              logs: [{message: 'RuntimeError: Must not contain PII', level: 'ERROR', count: 1,
                      stack_trace: a_string_including('REDACTED')}]
            )
            expect(event.payload).to include(
              logs: [{message: 'RuntimeError: Must not contain PII', level: 'ERROR', count: 1,
                      stack_trace: a_string_including("\n/spec/")}]
            )
            expect(event.payload[:logs].map { |log| log[:message] }).not_to include('p@ssw0rd')
          end

          begin
            raise 'Invalid token: p@ssw0rd'
          rescue => e
            component.report(e, level: :error, description: 'Must not contain PII')
          end
        end
      end
    end

    context 'with anonymous exception' do
      it 'sends a log event to via telemetry' do
        expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(
            logs: [{message: /#<Class:/, level: 'ERROR', count: 1,
                    stack_trace: a_string_including('REDACTED')}]
          )
          expect(event.payload).to include(
            logs: [{message: /#<Class:/, level: 'ERROR', count: 1,
                    stack_trace: a_string_including("\n/spec/")}]
          )
          expect(event.payload[:logs].map { |log| log[:message] }).not_to include('p@ssw0rd')
        end

        customer_exception = Class.new(StandardError)

        begin
          raise customer_exception, 'Invalid token: p@ssw0rd'
        rescue => e
          component.report(e, level: :error)
        end
      end
    end
    context 'with an Errno error carrying telemetry message' do
      subject(:report) do
        raise Errno::ENOENT, 'Dynamic message'
      rescue SystemCallError => error
        # This is normally done by native extensions, when raising Errno errors
        error.instance_variable_set(:@telemetry_message, 'Safe message')

        component.report(error, level: :error, description: description)
      end

      let(:description) { nil }

      it 'includes the telemetry message but not the dynamic exception message' do
        expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(
            logs: [{message: 'Errno::ENOENT: (Safe message)', level: 'ERROR', count: 1,
                    stack_trace: a_string_including('REDACTED')}]
          )
          expect(event.payload[:logs].map { |log| log[:message] }).not_to include('Dynamic message')
        end

        report
      end

      context 'with description' do
        let(:description) { 'Operation failed' }

        it 'includes both description and telemetry message' do
          expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
            expect(event.payload).to include(
              logs: [{message: 'Errno::ENOENT: Operation failed (Safe message)', level: 'ERROR', count: 1,
                      stack_trace: a_string_including('REDACTED')}]
            )
            expect(event.payload[:logs].map { |log| log[:message] }).not_to include('Dynamic message')
          end

          report
        end
      end
    end
    context 'with NativeError' do
      it 'includes the telemetry-safe message in telemetry' do
        expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(
            logs: [{message: 'RuntimeError: (Static message)', level: 'ERROR', count: 1,
                    stack_trace: a_string_including('REDACTED')}]
          )
          expect(event.payload[:logs].map { |log| log[:message] }).not_to include('Dynamic message')
        end
        begin
          error = ::RuntimeError.new('Dynamic message')
          error.instance_variable_set(:@telemetry_message, 'Static message')
          raise error
        rescue => e
          component.report(e, level: :error)
        end
      end
      context 'with description' do
        it 'includes both description and telemetry message' do
          expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
            expect(event.payload).to include(
              logs: [{message: 'RuntimeError: Static description (Static message)', level: 'ERROR', count: 1,
                      stack_trace: a_string_including('REDACTED')}]
            )
            expect(event.payload[:logs].map { |log| log[:message] }).not_to include('Dynamic message')
          end
          begin
            error = ::RuntimeError.new('Dynamic message')
            error.instance_variable_set(:@telemetry_message, 'Static message')
            raise error
          rescue => e
            component.report(e, level: :error, description: 'Static description')
          end
        end
      end
      context 'without telemetry message' do
        it 'omits the dynamic exception message from telemetry' do
          expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
            expect(event.payload).to include(
              logs: [{message: 'RuntimeError', level: 'ERROR', count: 1,
                      stack_trace: a_string_including('REDACTED')}]
            )
            expect(event.payload[:logs].map { |log| log[:message] }).not_to include('Dynamic message')
          end
          begin
            raise 'Dynamic message'
          rescue => e
            component.report(e, level: :error)
          end
        end
      end

      context 'with description and dynamic content' do
        it 'includes the description but not the dynamic exception message' do
          expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
            expect(event.payload).to include(
              logs: [{message: 'RuntimeError: Static description', level: 'ERROR', count: 1,
                      stack_trace: a_string_including('REDACTED')}]
            )
            expect(event.payload[:logs].map { |log| log[:message] }).not_to include(/memory address/)
          end
          begin
            raise 'Dynamic message'
          rescue => e
            component.report(e, level: :error, description: 'Static description')
          end
        end
      end
    end
  end

  describe '.error' do
    context 'with description' do
      it 'sends a log event to via telemetry' do
        expect(component).to receive(:log!).with(instance_of(Datadog::Core::Telemetry::Event::Log)) do |event|
          expect(event.payload).to include(logs: [{message: 'Must not contain PII', level: 'ERROR', count: 1}])
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
      rescue => e
        result = described_class.from(e)
      end

      expect(result).to start_with('/spec/datadog/core/telemetry/logging_spec.rb')
      expect(result).to end_with('REDACTED')
    end
  end
end
