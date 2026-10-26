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
        timeout_seconds,
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

  let(:compiler) { Datadog::DI::EL::Compiler.new }

  let(:settings) { instance_double(Datadog::Core::Configuration::Settings, dynamic_instrumentation: nil).as_null_object }
  let(:serializer) { instance_double(Datadog::DI::Serializer).as_null_object }

  def compile_expr(dsl_expr, ast)
    src, regexps = compiler.compile(ast)
    Datadog::DI::EL::Expression.new(dsl_expr, src, regexps: regexps)
  end

  # `collection.filter(@it >= 500)`, the collection-filter shape used
  # by the system test, with a predicate that selects only part of the
  # collection so the selected content is observable in assertions.
  let(:filter_expr) do
    compile_expr("collection.filter(@it >= 500)",
      "filter" => [{"ref" => "collection"}, {"ge" => [{"ref" => "@it"}, 500]}])
  end

  let(:filter_hash_expr) do
    compile_expr("collection.filter(@value >= 0)",
      "filter" => [{"ref" => "collection"}, {"ge" => [{"ref" => "@value"}, 0]}])
  end

  def context_with(collection)
    Datadog::DI::Context.new(
      probe: nil, settings: settings, serializer: serializer,
      locals: {collection: collection}
    )
  end

  describe "#filter, #all, #any evaluation deadline" do
    let(:all_expr) do
      compile_expr("collection.all(@it >= 0)",
        "all" => [{"ref" => "collection"}, {"ge" => [{"ref" => "@it"}, 0]}])
    end

    let(:any_expr) do
      compile_expr("collection.any(@it >= 0)",
        "any" => [{"ref" => "collection"}, {"ge" => [{"ref" => "@it"}, 0]}])
    end

    context "with the deadline already in the past" do
      let(:deadline) { Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID, :float_second) - 0.001 }

      # The abort raises at i == 0, before the predicate block runs, so the
      # Hash branch aborts before the @it predicate is reached.
      context "over an Array collection" do
        let(:collection) { Array.new(1000) { |i| i } }

        it "#filter raises EvaluationTimeout" do
          expect { filter_expr.satisfied?(context_with(collection), deadline: deadline) }
            .to raise_error(Datadog::DI::Error::EvaluationTimeout)
        end

        it "#all raises EvaluationTimeout" do
          expect { all_expr.satisfied?(context_with(collection), deadline: deadline) }
            .to raise_error(Datadog::DI::Error::EvaluationTimeout)
        end

        it "#any raises EvaluationTimeout" do
          expect { any_expr.satisfied?(context_with(collection), deadline: deadline) }
            .to raise_error(Datadog::DI::Error::EvaluationTimeout)
        end
      end

      context "over a Hash collection" do
        let(:collection) { Array.new(1000) { |i| ["key#{i}", i] }.to_h }

        it "#filter raises EvaluationTimeout" do
          expect { filter_expr.satisfied?(context_with(collection), deadline: deadline) }
            .to raise_error(Datadog::DI::Error::EvaluationTimeout)
        end

        it "#all raises EvaluationTimeout" do
          expect { all_expr.satisfied?(context_with(collection), deadline: deadline) }
            .to raise_error(Datadog::DI::Error::EvaluationTimeout)
        end

        it "#any raises EvaluationTimeout" do
          expect { any_expr.satisfied?(context_with(collection), deadline: deadline) }
            .to raise_error(Datadog::DI::Error::EvaluationTimeout)
        end
      end
    end

    context "with no deadline" do
      let(:collection) { Array.new(1000) { |i| i } }

      it "#filter returns the selected items" do
        expect(filter_expr.evaluate(context_with(collection), deadline: nil)).to eq((500..999).to_a)
      end

      it "#filter returns the selected entries of a Hash" do
        expect(filter_hash_expr.evaluate(
          context_with({"a" => 1, "b" => 2, "c" => -1}),
          deadline: nil,
        )).to eq({"a" => 1, "b" => 2})
      end
    end

    context "with the deadline far in the future" do
      let(:collection) { Array.new(1000) { |i| i } }
      let(:deadline) { Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID, :float_second) + 60.0 }

      it "#filter completes without timing out" do
        expect(filter_expr.evaluate(context_with(collection), deadline: deadline)).to eq((500..999).to_a)
      end
    end

    context "with the deadline exceeded midway through the collection" do
      let(:collection) { Array.new(1000) { |i| i } }

      # The cooperative check runs every EVALUATION_DEADLINE_CHECK_INTERVAL items.
      # Stub Process.clock_gettime so the first check (i=0) is before the
      # deadline and the second check (i=64) is after it, proving the timeout
      # raises at the second check, in mid-iteration.
      it "#filter raises after the first check interval" do
        deadline = 1.0
        checks = 0
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_THREAD_CPUTIME_ID, :float_second) do
          checks += 1
          (checks <= 1) ? deadline - 0.001 : deadline + 0.001
        end
        expect do
          filter_expr.satisfied?(context_with(collection), deadline: deadline)
        end.to raise_error(Datadog::DI::Error::EvaluationTimeout)
        expect(checks).to be >= 2
      end
    end

    context "with a compare_by_identity Hash collection" do
      let(:identity_collection) do
        source = {}
        source.compare_by_identity
        source["key"] = 1
        source[+"key"] = 2
        source
      end

      it "#filter preserves the distinct keys and the identity mode" do
        result = filter_hash_expr.evaluate(context_with(identity_collection), deadline: nil)
        expect(result.length).to eq(2)
        expect(result.compare_by_identity?).to be(true)
      end
    end

    context "with a nested evaluation of the same expression mid-iteration" do
      # The first collection item triggers a nested evaluate call on the same
      # Expression: isUndefined invokes nil? on the item, and the trigger's
      # nil? reenters evaluation. This reproduces on one thread the state
      # sharing that occurs when two threads evaluate the same probe
      # concurrently.

      # `collection.filter(isUndefined(@it) != true && marker == 'outer')`
      let(:filter_with_refs_expr) do
        compile_expr("collection.filter(isUndefined(@it) != true && marker == 'outer')",
          "filter" => [
            {"ref" => "collection"},
            {"and" => [
              {"ne" => [{"isUndefined" => {"ref" => "@it"}}, true]},
              {"eq" => [{"ref" => "marker"}, "outer"]},
            ]},
          ])
      end

      let(:trigger) do
        nested_expr = filter_with_refs_expr
        nested_context = context_with_marker([1, 2, 3], "inner")
        nested_deadline = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID, :float_second) - 0.001
        trigger = Object.new
        trigger.define_singleton_method(:nil?) do
          begin
            nested_expr.evaluate(nested_context, deadline: nested_deadline)
          rescue Datadog::DI::Error::EvaluationTimeout
            nil
          end
          false
        end
        trigger
      end

      def context_with_marker(collection, marker)
        Datadog::DI::Context.new(
          probe: nil, settings: settings, serializer: serializer,
          locals: {collection: collection, marker: marker}
        )
      end

      it "reads locals from the invoking evaluation's context" do
        result = filter_with_refs_expr.evaluate(context_with_marker([trigger, 2], "outer"), deadline: nil)
        expect(result).to eq([trigger, 2])
      end

      it "keeps the invoking evaluation's deadline" do
        # More than EVALUATION_DEADLINE_CHECK_INTERVAL items, so a deadline
        # check runs after the trigger item at index 0.
        collection = [trigger] + Array.new(70) { |i| i + 1 }
        deadline = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID, :float_second) + 60.0
        result = filter_with_refs_expr.evaluate(context_with_marker(collection, "outer"), deadline: deadline)
        expect(result).to eq(collection)
      end
    end
  end

  describe "#filter does not dispatch customer code" do
    context "over an Array subclass that overrides each" do
      let(:each_raising_array_class) do
        Class.new(Array) do
          def each
            raise "customer each dispatched during filter evaluation"
          end
        end
      end

      it "selects items without invoking the override" do
        collection = each_raising_array_class.new([400, 600, 700])
        expect(filter_expr.evaluate(context_with(collection), deadline: nil)).to eq([600, 700])
      end
    end

    context "over a Hash subclass that overrides each" do
      let(:each_raising_hash_class) do
        Class.new(Hash) do
          def each
            raise "customer each dispatched during filter evaluation"
          end
        end
      end

      it "selects entries without invoking the override" do
        collection = each_raising_hash_class.new
        collection["a"] = 1
        collection["b"] = -1
        expect(filter_hash_expr.evaluate(context_with(collection), deadline: nil)).to eq("a" => 1)
      end
    end

    context "over a Hash subclass that overrides compare_by_identity?" do
      let(:identity_raising_hash_class) do
        Class.new(Hash) do
          def compare_by_identity?
            raise "customer compare_by_identity? dispatched during filter evaluation"
          end
        end
      end

      it "preserves the identity mode without invoking the override" do
        collection = identity_raising_hash_class.new.compare_by_identity
        collection["key"] = 1
        collection[+"key"] = 2
        result = filter_hash_expr.evaluate(context_with(collection), deadline: nil)
        expect(result.length).to eq(2)
        expect(result.compare_by_identity?).to be(true)
      end
    end

    context "over a Hash whose keys raise from hash and eql?" do
      # The two keys hash to distinct values unarmed, so the selected
      # entries never collide in the result and eql? stays uncalled;
      # Ruby 3.1+'s Hash#select compares colliding keys through eql?.
      let(:raising_key_class) do
        Class.new do
          class << self
            attr_accessor :methods_raise
          end

          def initialize(n)
            @n = n
          end

          def hash
            raise "customer key hash dispatched during filter evaluation" if self.class.methods_raise
            @n
          end

          def eql?(other)
            raise "customer key eql? dispatched during filter evaluation" if self.class.methods_raise
            equal?(other)
          end
        end
      end

      # Earlier Rubies' Hash#select rehashes the keys, so the copy without
      # key-method invocations exists only from Ruby 3.1 on.
      it "selects entries without invoking the key methods" do
        skip "Hash#select copies entries without rehashing only from Ruby 3.1" if Datadog::RubyVersion.is?("< 3.1")
        key_a = raising_key_class.new(1)
        key_b = raising_key_class.new(2)
        collection = {key_a => 1, key_b => -1}
        raising_key_class.methods_raise = true
        result = filter_hash_expr.evaluate(context_with(collection), deadline: nil)
        raising_key_class.methods_raise = false
        expect(result).to eq(key_a => 1)
      end
    end
  end

  describe Datadog::DI::EL::Compiler do
    let(:compiler) { described_class.new }

    it "precompiles a literal matches needle at compile time" do
      code, regexps = compiler.compile({"matches" => [{"ref" => "var"}, "hello[a-z]"]})

      expect(code).to eq("matches_compiled(ref(context, 'var'), 0)")
      expect(regexps.length).to eq(1)
      expect(regexps.first).to be_a(Regexp)
    end

    it "compiles a dynamically-computed matches needle at evaluation time" do
      code, regexps = compiler.compile({"matches" => [{"ref" => "var"}, {"ref" => "pat"}]})

      expect(code).to eq("matches(ref(context, 'var'), (ref(context, 'pat')))")
      expect(regexps).to be_empty
    end

    it "rejects an invalid literal matches needle at compile time" do
      expect {
        compiler.compile({"matches" => [{"ref" => "var"}, "[invalid"]})
      }.to raise_error(Datadog::DI::Error::InvalidExpression, /Invalid regular expression in matches/)
    end
  end
end
