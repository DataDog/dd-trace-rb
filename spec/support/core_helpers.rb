module CoreHelpers
  # Asserts that a deprecated action is recorded by the `subject` execution.
  RSpec.shared_examples 'records deprecated action' do |matcher = nil|
    it 'records deprecated action in the deprecation log' do
      expect { subject }.to log_deprecation(matcher)
    end
  end

  # Test matcher for this library's deprecated operation recorder.
  #
  # @example Matching the message
  #   expect { subject }.to log_deprecation(include('deprecated_option'))
  # @example Matching any message
  #   expect { subject }.to log_deprecation
  # @example Allowing no deprecation logging
  #   expect { subject }.to_not log_deprecation
  # @example Negate message matching
  #   expect { subject }.to_not log_deprecation(include('no_longer_deprecated_option'))
  RSpec::Matchers.define :log_deprecation do |message_matcher|
    match(notify_expectation_failures: true) do |block|
      expect(::Datadog::Core).to receive(:log_deprecation).with(no_args) do |&message_block|
        expect(message_block.call).to match(message_matcher) if message_matcher
      end

      block.call

      true
    end

    match_when_negated(notify_expectation_failures: true) do |block|
      if message_matcher
        allow(::Datadog::Core).to receive(:log_deprecation).with(no_args) do |&message_block|
          expect(message_block.call).to_not match(message_matcher)
        end
      else
        expect(::Datadog::Core).to_not receive(:log_deprecation)
      end

      block.call

      true
    end

    supports_block_expectations

    def supports_value_expectations?
      false
    end
  end
end
