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

  RSpec::Matchers.define :raise_native_error do |expected_class, expected_message = nil, expected_telemetry_message = nil, &block|
    unless expected_class.is_a?(Class) && expected_class <= Datadog::Core::Native::Error
      raise ArgumentError, "expected_class must be a subclass of Datadog::Core::Native::Error"
    end

    supports_block_expectations

    def describe_expected(value)
      if value.respond_to?(:description) && value.description
        value.description
      else
        value.inspect
      end
    end

    def match_expected?(expected, actual, attribute)
      return true if expected.nil?

      actual_description = actual.nil? ? "nil" : actual.inspect

      failure_message = if expected.respond_to?(:matches?)
        unless expected.matches?(actual)
          if expected.respond_to?(:failure_message)
            expected.failure_message
          else
            "expected native exception #{attribute} to match #{describe_expected(expected)}, but was #{actual_description}"
          end
        end
      elsif expected.is_a?(Regexp)
        actual_string = if actual.is_a?(String)
          actual
        elsif actual.respond_to?(:to_str)
          actual.to_str
        end
        unless actual_string && expected.match?(actual_string)
          "expected native exception #{attribute} to match #{expected.inspect}, but was #{actual_description}"
        end
      else
        unless actual == expected
          "expected native exception #{attribute} to equal #{expected.inspect}, but was #{actual_description}"
        end
      end

      if failure_message
        @failure_message ||= failure_message
        false
      else
        true
      end
    end

    match do |actual_proc|
      @failure_message = nil
      @actual_error = nil

      actual_proc.call
      false
    rescue Datadog::Core::Native::Error => e
      @actual_error = e

      unless e.is_a?(expected_class)
        @failure_message =
          "expected native exception of class #{expected_class}, but #{e.class} was raised"
        return false
      end

      message_matches = match_expected?(expected_message, e.message, "message")
      telemetry_matches = match_expected?(expected_telemetry_message, e.telemetry_message, "telemetry message")

      return false unless message_matches && telemetry_matches

      block&.call(e)

      true
    end

    failure_message do
      if @actual_error
        @failure_message ||
          "expected native exception of class #{expected_class} with message #{expected_message.inspect} " \
          "and telemetry message #{expected_telemetry_message.inspect}, but got #{@actual_error.class} " \
          "with message #{@actual_error.message.inspect} and telemetry message #{@actual_error.telemetry_message.inspect}"
      else
        "expected native exception of class #{expected_class} with message #{expected_message.inspect} " \
        "and telemetry message #{expected_telemetry_message.inspect}, but no exception was raised"
      end
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
