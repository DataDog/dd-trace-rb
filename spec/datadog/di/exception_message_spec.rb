require "datadog/di/spec_helper"

RSpec.describe 'exception_message' do
  subject(:message) do
    Datadog::DI.exception_message(exception)
  end

  context 'standard library exception class' do
    context 'when constructor argument is a string' do
      let(:exception) do
        NameError.new('No method foo in bar')
      end

      it 'returns the string provided to constructor' do
        expect(message).to eq 'No method foo in bar'
      end
    end

    context 'when constructor argument is not a string' do
      let(:object) do
        Object.new.freeze
      end

      let(:exception) do
        NameError.new(object)
      end

      it 'returns the argument provided to constructor' do
        expect(message).to be object
      end
    end
  end

  context 'a custom exception class with overridden message method' do
    let(:exception_class) do
      Class.new(StandardError) do
        define_method(:message) do
          'custom message'
        end
      end
    end

    let(:object) do
      Object.new.freeze
    end

    let(:exception) do
      exception_class.new(object)
    end

    it 'returns the argument provided to constructor' do
      # The message obtained from +exception_message+ ignores the
      # Ruby +message+ method override.
      expect(message).to be object

      # Check that +message+ is overridden.
      expect(exception.message).to eq('custom message')
    end
  end
end
