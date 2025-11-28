module CoreHelpers
  RSpec.shared_context 'non-development execution environment' do
    before { allow(Datadog::Core::Environment::Execution).to receive(:development?).and_return(false) }
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
      expectation = expect(::Datadog::Core).to receive(:log_deprecation).with(any_args) do |&message_block|
        expect(message_block.call).to match(message_matcher) if message_matcher
      end

      @recorded_customizations&.each do |customization|
        customization.playback_onto(expectation)
      end

      block.call

      true
    end

    match_when_negated(notify_expectation_failures: true) do |block|
      if message_matcher
        allow(::Datadog::Core).to receive(:log_deprecation).with(any_args) do |&message_block|
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

    # Add support for `once`, `at_least`, and other chained matchers from `RSpec::Mocks::Matchers::Receive`
    own_methods = (instance_methods - superclass.instance_methods)
    ::RSpec::Mocks::MessageExpectation.public_instance_methods(false).each do |method|
      next if own_methods.include?(method)

      define_method(method) do |*args, &block|
        @recorded_customizations ||= []
        @recorded_customizations << ::RSpec::Mocks::Matchers::ExpectationCustomization.new(method, args, block)
        self
      end
      ruby2_keywords(method) if respond_to?(:ruby2_keywords, true)
    end
  end

  module ClassMethods
    def skip_unless_integration_testing_enabled
      unless ENV['TEST_DATADOG_INTEGRATION']
        before(:all) do
          skip 'Set TEST_DATADOG_INTEGRATION=1 in environment to run this test'
        end
      end
    end

    # Positional and keyword arguments are both accepted to make the method
    # work on Ruby 2.5/2.6 and 2.7+. In practice only one type of arguments
    # should be used in any given call.
    def with_env(*args, **opts)
      if args.any? && opts.any? # rubocop:disable Style/IfUnlessModifier
        raise ArgumentError, 'Do not pass both args and opts'
      end

      around do |example|
        if args.any?
          ClimateControl.modify(*args) do
            example.run
          end
        else
          ClimateControl.modify(**opts) do
            example.run
          end
        end
      end
    end
  end

  def self.included(base)
    base.extend ClassMethods
  end
end
