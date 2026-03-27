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

    it 'returns an array of strings' do
      expect(backtrace).to be_an(Array)
      expect(backtrace).not_to be_empty
      expect(backtrace.first).to be_a(String)
      expect(backtrace.first).to match(/\A.+:\d+:in\s/)
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

  context 'when exception class overrides backtrace method' do
    let(:exception_class) do
      Class.new(StandardError) do
        define_method(:backtrace) do
          ['overridden']
        end
      end
    end

    let(:exception) do
      raise exception_class, 'test'
    rescue => e
      e
    end

    it 'returns the real backtrace, not the overridden one' do
      # The raw backtrace from the C extension bypasses the override.
      expect(backtrace).to be_an(Array)
      expect(backtrace).not_to eq(['overridden'])
      expect(backtrace.first).to match(/\A.+:\d+:in\s/)

      # Verify the override exists on the Ruby side.
      expect(exception.backtrace).to eq(['overridden'])
    end
  end
end
