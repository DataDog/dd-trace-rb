require 'spec_helper'
require_relative '../spec_helper'
require 'datadog/di/el'

RSpec.describe Datadog::DI::EL::Evaluator do
  di_test

  let(:evaluator) { described_class.new }

  # Shared catastrophic-backtracking fixtures, used by both the runtime
  # #matches path (needle compiled per call) and the precompiled
  # #matches_compiled path (needle compiled once, ahead of time). The
  # haystack length is chosen so that the unbounded baseline match takes
  # over 5 seconds on every supported Ruby version (verified locally on
  # 2.5 through 3.4) -- enough that the configured timeout is the operative
  # bound on observed elapsed time. With the timeout in place, the call
  # must instead abort after approximately that timeout.
  #
  # Catastrophic-backtracking pattern: ambiguous nested quantifier combined
  # with a backreference. The backreference also defeats the match-cache
  # optimisation introduced in Ruby 3.2.
  let(:pattern) { '^([a-z]+)*\1$' }
  let(:haystack_length) { 30 }
  let(:haystack) { ('a' * haystack_length) + '1' }

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

  # Tolerance below the configured timeout: small margin for
  # CLOCK_MONOTONIC measurement noise between the start sample and the
  # regexp engine arming its timer.
  clock_skew_margin_seconds = 0.05

  # Tolerance above the configured timeout: absorbs Timeout.timeout's
  # ~100ms sleeper-thread granularity on Ruby < 3.2 (measured locally on
  # 2.6 through 3.1) plus scheduler variance under CI load. Half a second
  # is well above the measured overshoot and well below the 0.8s gap
  # between the two timeout values exercised below.
  overshoot_budget_seconds = 0.5

  # The two timeouts below each assert that the observed wall-clock time
  # tracks the configured value. Running both demonstrates that the timeout
  # is actually controlling behavior, rather than the regexp finishing
  # naturally or some unrelated bound being hit. The upper bound for the
  # smaller timeout stays below the lower bound for the larger one, so
  # swapping the two values would cause both cases to fail.
  #
  # +do_match+ is defined by the including context to invoke the operator
  # under test (runtime or precompiled) against +haystack+ and +pattern+.
  shared_examples 'aborts after approximately the configured timeout' do |timeout_seconds|
    before do
      stub_const(
        'Datadog::DI::EL::Evaluator::MATCHES_TIMEOUT_SECONDS',
        timeout_seconds
      )
    end

    it "raises a timeout error after approximately #{timeout_seconds}s" do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect {
        do_match
      }.to raise_error(expected_timeout_error)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      # Lower bound: the regexp must have actually waited for the timeout
      # -- otherwise the regexp finished naturally and the timeout did
      # nothing.
      expect(elapsed).to be >= timeout_seconds - clock_skew_margin_seconds

      # Upper bound: the regexp must not be running unbounded, and the
      # elapsed time must track the configured timeout (not some other
      # value).
      expect(elapsed).to be <= timeout_seconds + overshoot_budget_seconds
    end
  end

  shared_examples 'a timeout-bounded matcher' do
    context 'with a short timeout' do
      include_examples 'aborts after approximately the configured timeout', 0.2
    end

    context 'with a longer timeout' do
      include_examples 'aborts after approximately the configured timeout', 1.0
    end
  end

  describe '#matches' do
    context 'with a well-formed pattern' do
      it 'returns true when the haystack matches' do
        expect(evaluator.matches('hello world', 'hello[a-z ]+')).to be(true)
      end

      it 'returns false when the haystack does not match' do
        expect(evaluator.matches('xyz', 'hello[a-z]')).to be(false)
      end
    end

    context 'with a pathological pattern that would otherwise run for many seconds' do
      # Needle computed at evaluation time, so the regexp is compiled on
      # each call.
      def do_match
        evaluator.matches(haystack, pattern)
      end

      include_examples 'a timeout-bounded matcher'
    end
  end

  describe '#matches_compiled' do
    # The regexp is built once, with the per-call timeout baked in on Ruby
    # 3.2+, and stored in +regexps+ -- mirroring how the Compiler
    # precompiles literal needles at expression-compile time.
    let(:evaluator) do
      described_class.new([described_class.compile_regexp(compiled_pattern)])
    end

    context 'with a well-formed pattern' do
      context 'when the haystack matches' do
        let(:compiled_pattern) { 'hello[a-z ]+' }

        it 'returns true' do
          expect(evaluator.matches_compiled('hello world', 0)).to be(true)
        end
      end

      context 'when the haystack does not match' do
        let(:compiled_pattern) { 'hello[a-z]' }

        it 'returns false' do
          expect(evaluator.matches_compiled('xyz', 0)).to be(false)
        end
      end
    end

    context 'with a pathological pattern that would otherwise run for many seconds' do
      let(:compiled_pattern) { pattern }

      def do_match
        evaluator.matches_compiled(haystack, 0)
      end

      include_examples 'a timeout-bounded matcher'
    end
  end

  describe Datadog::DI::EL::Compiler do
    let(:compiler) { described_class.new }

    it 'precompiles a literal matches needle at compile time' do
      code, regexps = compiler.compile({'matches' => [{'ref' => 'var'}, 'hello[a-z]']})

      expect(code).to eq("matches_compiled(ref('var'), 0)")
      expect(regexps.length).to eq(1)
      expect(regexps.first).to be_a(Regexp)
    end

    it 'compiles a dynamically-computed matches needle at evaluation time' do
      code, regexps = compiler.compile({'matches' => [{'ref' => 'var'}, {'ref' => 'pat'}]})

      expect(code).to eq("matches(ref('var'), (ref('pat')))")
      expect(regexps).to be_empty
    end

    it 'falls back to evaluation-time compilation for an invalid literal needle' do
      code, regexps = compiler.compile({'matches' => [{'ref' => 'var'}, '[invalid']})

      expect(code).to eq("matches(ref('var'), (\"[invalid\"))")
      expect(regexps).to be_empty
    end
  end
end
