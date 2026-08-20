require "spec_helper"
require_relative "../spec_helper"
require "datadog/di/el"

RSpec.describe Datadog::DI::EL::Evaluator do
  di_test

  let(:evaluator) { described_class.new }

  # Shared catastrophic-backtracking fixtures.
  #
  # Haystack length is chosen so that the unbounded baseline match takes
  # over 5 seconds on every supported Ruby version (verified locally on
  # 2.5 through 3.4).
  #
  # Catastrophic-backtracking pattern: ambiguous nested quantifier combined
  # with a backreference. The backreference also defeats the match-cache
  # optimisation introduced in Ruby 3.2.
  let(:pattern) { '^([a-z]+)*\1$' }
  let(:haystack_length) { 30 }
  let(:haystack) { ("a" * haystack_length) + "1" }

  # Regexp::TimeoutError was introduced in Ruby 3.2 and inherits from
  # RegexpError. Timeout::Error (used on older Rubies) inherits from
  # RuntimeError. The expected class is selected by Ruby version.
  let(:expected_timeout_error) do
    if Datadog::RubyVersion.is?(">= 3.2")
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
  # naturally or some unrelated bound being hit.
  #
  # +do_match+ is defined by the including context to invoke the operator
  # under test (runtime or precompiled) against +haystack+ and +pattern+.
  shared_examples "aborts after approximately the configured timeout" do |timeout_seconds|
    before do
      stub_const(
        "Datadog::DI::EL::Evaluator::MATCHES_TIMEOUT_SECONDS",
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

  shared_examples "a timeout-bounded matcher" do
    context "with a short timeout" do
      include_examples "aborts after approximately the configured timeout", 0.2
    end

    context "with a longer timeout" do
      include_examples "aborts after approximately the configured timeout", 1.0
    end
  end

  describe "#matches" do
    context "with a well-formed pattern" do
      it "returns true when the haystack matches" do
        expect(evaluator.matches("hello world", "hello[a-z ]+")).to be(true)
      end

      it "returns false when the haystack does not match" do
        expect(evaluator.matches("xyz", "hello[a-z]")).to be(false)
      end
    end

    context "with a pathological pattern that would otherwise run for many seconds" do
      # Needle computed at evaluation time, so the regexp is compiled on
      # each call.
      def do_match
        evaluator.matches(haystack, pattern)
      end

      include_examples "a timeout-bounded matcher"
    end
  end

  describe "#matches_compiled" do
    # The regexp is built once, with the per-call timeout baked in on Ruby
    # 3.2+, and stored in +regexps+ -- mirroring how the Compiler
    # precompiles literal needles at expression-compile time.
    let(:evaluator) do
      described_class.new([described_class.compile_regexp(compiled_pattern)])
    end

    context "with a well-formed pattern" do
      context "when the haystack matches" do
        let(:compiled_pattern) { "hello[a-z ]+" }

        it "returns true" do
          expect(evaluator.matches_compiled("hello world", 0)).to be(true)
        end
      end

      context "when the haystack does not match" do
        let(:compiled_pattern) { "hello[a-z]" }

        it "returns false" do
          expect(evaluator.matches_compiled("xyz", 0)).to be(false)
        end
      end
    end

    context "with a pathological pattern that would otherwise run for many seconds" do
      let(:compiled_pattern) { pattern }

      def do_match
        evaluator.matches_compiled(haystack, 0)
      end

      include_examples "a timeout-bounded matcher"
    end
  end

  describe "#filter, #all, #any evaluation deadline" do
    let(:compiler) { Datadog::DI::EL::Compiler.new }

    let(:settings) { instance_double("settings", dynamic_instrumentation: nil).as_null_object }
    let(:serializer) { instance_double("serializer").as_null_object }

    # `largeCollection.filter(@it >= 0)` — the collection-filter shape used by
    # the system test, exercising the cooperative deadline inside #filter.
    let(:filter_expr) do
      src, regexps = compiler.compile({
        "filter" => [{"ref" => "collection"}, {"ge" => [{"ref" => "@it"}, 0]}],
      })
      Datadog::DI::EL::Expression.new("collection.filter(@it >= 0)", src, regexps: regexps)
    end

    # `largeCollection.all(@it >= 0)` and `...any(@it >= 0)` exercise #all/#any.
    let(:all_expr) do
      src, regexps = compiler.compile({
        "all" => [{"ref" => "collection"}, {"ge" => [{"ref" => "@it"}, 0]}],
      })
      Datadog::DI::EL::Expression.new("collection.all(@it >= 0)", src, regexps: regexps)
    end

    let(:any_expr) do
      src, regexps = compiler.compile({
        "any" => [{"ref" => "collection"}, {"ge" => [{"ref" => "@it"}, 0]}],
      })
      Datadog::DI::EL::Expression.new("collection.any(@it >= 0)", src, regexps: regexps)
    end

    def context_with(collection, deadline_ns:)
      Datadog::DI::Context.new(
        probe: nil, settings: settings, serializer: serializer,
        locals: {collection: collection}, deadline_ns: deadline_ns
      )
    end

    context "with the deadline already in the past" do
      let(:collection) { Array.new(1000) { |i| i } }
      let(:deadline_ns) { Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - 1 }

      it "#filter raises EvaluationTimeout without consuming the whole collection" do
        expect { filter_expr.satisfied?(context_with(collection, deadline_ns: deadline_ns)) }
          .to raise_error(Datadog::DI::Error::EvaluationTimeout)
      end

      it "#all raises EvaluationTimeout" do
        expect { all_expr.satisfied?(context_with(collection, deadline_ns: deadline_ns)) }
          .to raise_error(Datadog::DI::Error::EvaluationTimeout)
      end

      it "#any raises EvaluationTimeout" do
        expect { any_expr.satisfied?(context_with(collection, deadline_ns: deadline_ns)) }
          .to raise_error(Datadog::DI::Error::EvaluationTimeout)
      end
    end

    context "with no deadline" do
      let(:collection) { Array.new(1000) { |i| i } }

      it "#filter returns the selected items (behavior unchanged)" do
        # @it >= 0 is true for every element, so the filtered result is
        # the whole collection and no timeout is raised.
        expect(filter_expr.satisfied?(context_with(collection, deadline_ns: nil))).to be(true)
      end
    end

    context "with the deadline far in the future" do
      let(:collection) { Array.new(1000) { |i| i } }
      let(:deadline_ns) { Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + 60_000_000_000 }

      it "#filter completes without timing out" do
        expect(filter_expr.satisfied?(context_with(collection, deadline_ns: deadline_ns))).to be(true)
      end
    end

    context "with the deadline crossed midway through the collection" do
      let(:collection) { Array.new(1000) { |i| i } }

      # The cooperative check fires every EVALUATION_DEADLINE_CHECK_INTERVAL items.
      # Drive Process.clock_gettime so the first check (i=0) is before the
      # deadline and the second check (i=64) is after it, proving the bound
      # engages mid-iteration rather than at the first item.
      it "#filter raises after the first interval's worth of items" do
        deadline_ns = 1_000_000_000
        checks = 0
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond) do
          checks += 1
          checks <= 1 ? deadline_ns - 1 : deadline_ns + 1
        end
        # Going through #satisfied? sets @context on the evaluator (the
        # compiled evaluate method does this), so #filter can read the
        # per-invocation deadline. The two-phase stub makes the first
        # check pass and the second fail, so the raise is not immediate.
        expect do
          filter_expr.satisfied?(context_with(collection, deadline_ns: deadline_ns))
        end.to raise_error(Datadog::DI::Error::EvaluationTimeout)
        expect(checks).to be >= 2
      end
    end
  end

  describe Datadog::DI::EL::Compiler do
    let(:compiler) { described_class.new }

    it "precompiles a literal matches needle at compile time" do
      code, regexps = compiler.compile({"matches" => [{"ref" => "var"}, "hello[a-z]"]})

      expect(code).to eq("matches_compiled(ref('var'), 0)")
      expect(regexps.length).to eq(1)
      expect(regexps.first).to be_a(Regexp)
    end

    it "compiles a dynamically-computed matches needle at evaluation time" do
      code, regexps = compiler.compile({"matches" => [{"ref" => "var"}, {"ref" => "pat"}]})

      expect(code).to eq("matches(ref('var'), (ref('pat')))")
      expect(regexps).to be_empty
    end

    it "rejects an invalid literal matches needle at compile time" do
      expect {
        compiler.compile({"matches" => [{"ref" => "var"}, "[invalid"]})
      }.to raise_error(Datadog::DI::Error::InvalidExpression, /Invalid regular expression in matches/)
    end
  end
end
