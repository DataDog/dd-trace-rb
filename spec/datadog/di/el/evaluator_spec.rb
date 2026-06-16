require 'spec_helper'
require_relative '../spec_helper'
require 'datadog/di/el'

RSpec.describe Datadog::DI::EL::Evaluator do
  di_test

  describe '#matches' do
    let(:evaluator) { described_class.new }

    context 'with a well-formed pattern' do
      it 'returns true when the haystack matches' do
        expect(evaluator.matches('hello world', 'hello[a-z ]+')).to be(true)
      end

      it 'returns false when the haystack does not match' do
        expect(evaluator.matches('xyz', 'hello[a-z]')).to be(false)
      end
    end

    # The pattern below is a classic catastrophic-backtracking case that
    # takes well over 5 seconds to match on every supported Ruby version
    # (verified locally on 2.5 through 3.4). With a per-`matches` timeout
    # in place, the call must instead abort after approximately the
    # configured timeout. The two contexts below each set a different
    # timeout and assert that the observed wall-clock time tracks the
    # configured value -- this is how the test demonstrates that the
    # timeout is actually controlling behavior (rather than the regexp
    # finishing naturally or some unrelated bound being hit).
    context 'with a pathological pattern that would otherwise run for many seconds' do
      let(:pattern) { '^([a-z]+)*\1$' }
      let(:haystack) { ('a' * 30) + '1' }

      # Regexp::TimeoutError was introduced in Ruby 3.2 and inherits from
      # RegexpError. Timeout::Error (used on older Rubies) inherits from
      # RuntimeError. The expected class is selected by Ruby version.
      let(:expected_timeout_error) do
        if RUBY_VERSION >= '3.2'
          Regexp::TimeoutError
        else
          Timeout::Error
        end
      end

      shared_examples 'aborts after approximately the configured timeout' do |timeout_seconds, upper_bound_seconds|
        before do
          stub_const(
            'Datadog::DI::EL::Evaluator::MATCHES_TIMEOUT_SECONDS',
            timeout_seconds
          )
        end

        it "raises a timeout error after approximately #{timeout_seconds}s" do
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          expect {
            evaluator.matches(haystack, pattern)
          }.to raise_error(expected_timeout_error)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

          # Lower bound: the regexp must have actually waited for the
          # timeout -- otherwise the regexp finished naturally and the
          # timeout did nothing.
          expect(elapsed).to be >= timeout_seconds - 0.05

          # Upper bound: the regexp must not be running unbounded. The
          # bound is generous to absorb Timeout.timeout's ~100ms overshoot
          # on Ruby < 3.2 and additional scheduler variance under CI load.
          expect(elapsed).to be <= upper_bound_seconds
        end
      end

      context 'with timeout set to 0.2 seconds' do
        # Realistic elapsed: ~0.2s on Ruby 3.2+, ~0.3s on Ruby < 3.2.
        # Upper bound 0.6s leaves ~0.3s headroom for CI variance while
        # still being well below the 0.95s lower bound of the 1.0s case.
        include_examples 'aborts after approximately the configured timeout', 0.2, 0.6
      end

      context 'with timeout set to 1.0 seconds' do
        # Realistic elapsed: ~1.0s on Ruby 3.2+, ~1.1s on Ruby < 3.2.
        include_examples 'aborts after approximately the configured timeout', 1.0, 1.5
      end
    end
  end
end
