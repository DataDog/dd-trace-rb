module CoreHelpers
  LOWERCASE_UUID_REGEXP = /\A[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}\z/

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

  RSpec::Matchers.define :be_valid_uuid do
    match do |actual|
      actual =~ CoreHelpers::LOWERCASE_UUID_REGEXP
    end

    failure_message do |actual|
      "expected #{actual.inspect} to be a valid lowercase UUID"
    end
  end

  def skip_if_libdatadog_not_supported(testcase)
    testcase.skip("Testcase requires libdatadog and it is not supported on JRuby") if PlatformHelpers.jruby?
    testcase.skip("Testcase requires libdatadog and it is not supported on TruffleRuby") if PlatformHelpers.truffleruby?

    return if Datadog::Core::LIBDATADOG_API_FAILURE.nil?

    raise "Libdatadog does not seem to be available: #{Datadog::Core::LIBDATADOG_API_FAILURE}. " \
      "Try running `bundle exec rake compile` before running this test."
  end
  module ClassMethods
    def skip_unless_integration_testing_enabled
      unless ENV['TEST_DATADOG_INTEGRATION']
        before(:all) do
          skip 'Set TEST_DATADOG_INTEGRATION=1 in environment to run this test'
        end
      end
    end

    def skip_unless_fork_supported
      unless Process.respond_to?(:fork)
        before(:all) do
          skip 'Fork is not supported on current platform'
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

    # Resets Components AtForkMonkeyPatch registration state.
    # Use this at describe/context level in tests that exercise or
    # assert on the forking behavior of components.
    def reset_at_fork_monkey_patch_for_components!
      # This helper uses `before` and not `before(all)` due to feedback in
      # https://github.com/DataDog/dd-trace-rb/pull/5315 and
      # https://github.com/DataDog/dd-trace-rb/pull/5304
      # where reviewers preferred to have the state reset for each test.
      #
      # The only time when the state should be reset per-test is when the
      # same describe/context block tests both the AtForkMonkeyPatch itself
      # and one of its clients. Our existing tests for the monkey patch itself
      # do not use this helper as of this writing.
      #
      # In practice, in our current test suite, it is safe to reset the
      # monkey patch state once per test file.
      before do
        # Unit tests for at fork monkey patch module reset its state,
        # including the defined handlers.
        # We need to make sure that the handler for Components is registered,
        # because normally it would be added during library initialization
        # and after the fork monkey patch test runs, the handler would get
        # cleared out.
        Datadog::Core::Configuration::Components.const_get(:AT_FORK_ONLY_ONCE).send(:reset_ran_once_state_for_tests)

        # We also need to clear out the handlers because we could have
        # the handlers registered from the library initialization time,
        # if the at fork monkey patch unit test did not yet run.
        # In this case the handlers that are already registered would be
        # executed twice which is 1) probably not good and 2) would fail
        # our assertions.
        Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_CHILD_BLOCKS).clear
      end
    end
  end

  def self.included(base)
    base.extend ClassMethods
  end
end
