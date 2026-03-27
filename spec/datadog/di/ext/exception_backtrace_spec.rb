require "datadog/di/spec_helper"

RSpec.describe 'exception_backtrace' do
  subject(:backtrace) do
    Datadog::DI.exception_backtrace(exception)
  end

  context 'when exception has a backtrace' do
    let(:exception) do
      raise StandardError, 'test'
    rescue => e
      e
    end

    it 'returns an array of Thread::Backtrace::Location' do
      expect(backtrace).to be_an(Array)
      expect(backtrace).not_to be_empty
      expect(backtrace.first).to be_a(Thread::Backtrace::Location)
      expect(backtrace.first.path).to be_a(String)
      expect(backtrace.first.lineno).to be_a(Integer)
    end
  end

  context 'when exception has no backtrace' do
    let(:exception) do
      StandardError.new('no backtrace')
    end

    it 'returns nil' do
      expect(backtrace).to be_nil
    end
  end

  context 'when exception class overrides backtrace_locations method' do
    let(:exception_class) do
      Class.new(StandardError) do
        define_method(:backtrace_locations) do
          []
        end
      end
    end

    let(:exception) do
      raise exception_class, 'test'
    rescue => e
      e
    end

    it 'returns the real backtrace, not the overridden one' do
      # The UnboundMethod bypasses the subclass override.
      expect(backtrace).to be_an(Array)
      expect(backtrace).not_to be_empty
      expect(backtrace.first).to be_a(Thread::Backtrace::Location)

      # Verify the override exists on the Ruby side.
      expect(exception.backtrace_locations).to eq([])
    end
  end
end
