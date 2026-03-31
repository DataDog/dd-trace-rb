require "datadog/di/spec_helper"

RSpec.describe 'EXCEPTION_BACKTRACE_LOCATIONS' do
  subject(:backtrace) do
    Datadog::DI::EXCEPTION_BACKTRACE_LOCATIONS.bind(exception).call
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

  context 'when backtrace was set via set_backtrace with strings' do
    let(:exception) do
      e = StandardError.new('wrapped')
      e.set_backtrace(['/app/foo.rb:10:in `bar\'', '/app/baz.rb:20:in `qux\''])
      e
    end

    it 'returns nil for backtrace_locations' do
      # set_backtrace with Array<String> causes backtrace_locations to
      # return nil — the VM cannot reconstruct Location objects from
      # formatted strings.
      expect(backtrace).to be_nil
    end
  end
end

RSpec.describe 'EXCEPTION_BACKTRACE' do
  subject(:backtrace) do
    Datadog::DI::EXCEPTION_BACKTRACE.bind(exception).call
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
          ['overridden:0:in `fake\'']
        end
      end
    end

    let(:exception) do
      raise exception_class, 'test'
    rescue => e
      e
    end

    it 'returns the real backtrace, not the overridden one' do
      expect(backtrace).to be_an(Array)
      expect(backtrace).not_to be_empty
      # The real backtrace contains the actual file path, not the override.
      expect(backtrace.first).not_to eq('overridden:0:in `fake\'')

      # Verify the override exists on the Ruby side.
      expect(exception.backtrace).to eq(['overridden:0:in `fake\''])
    end
  end

  context 'when backtrace was set via set_backtrace with strings' do
    let(:exception) do
      e = StandardError.new('wrapped')
      e.set_backtrace(['/app/foo.rb:10:in `bar\'', '/app/baz.rb:20:in `qux\''])
      e
    end

    it 'returns the string backtrace' do
      expect(backtrace).to eq(['/app/foo.rb:10:in `bar\'', '/app/baz.rb:20:in `qux\''])
    end
  end
end
