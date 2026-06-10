require "datadog/di/spec_helper"
require 'datadog/di/instrumenter'
require 'datadog/di/code_tracker'
require 'datadog/di/serializer'
require 'datadog/di/probe'
require 'datadog/di/proc_responder'
require 'logger'

# Pins down method-probe wrapper behavior under three Ruby dispatch
# scenarios that the existing test suite does not exercise:
#
#   1. Fiber switches inside a probed method body (Fiber.yield + resume)
#   2. Ractor isolation when a probed method is invoked inside a Ractor
#   3. Refinements visibility through the method-probe prepend chain
#
# Each scenario was a stated edge-case concern when comparing the
# do_super-lambda form of the method-probe wrapper to a hypothetical
# block + yield form. None of these scenarios had explicit test
# coverage in spec/datadog/di/ before this file; this fixes that gap.
#
# The tests document the current behavior on master. Any future
# refactor of the method-probe wrapper (PR #5560's re-entrancy guard,
# alternative wrapper forms, C-implemented wrappers) should keep these
# assertions green or update them deliberately with a rationale.

# The fixture classes below are defined at top-level so #hook_method
# can resolve them by name through ProbeManager-equivalent paths. They
# are deliberately tiny: the tests are about wrapper-dispatch
# semantics, not about snapshot content.

begin
  Object.send(:remove_const, :FiberDispatchFixture)
rescue NameError
end
class FiberDispatchFixture
  attr_reader :resumed_count

  def initialize
    @resumed_count = 0
  end

  # Yields control back to the fiber's resumer in the middle of the
  # method body, then returns. The probe fires on this method, so
  # the wrapper's enter/leave_probe (or any equivalent guard
  # bracketing in future implementations) must survive the
  # Fiber.yield/resume round trip.
  def yield_then_return(label)
    @resumed_count += 1
    Fiber.yield(label)
    "returned-#{label}"
  end

  # Bare method that does not yield. Used as the "outer" method when
  # nesting probed calls across fiber switches.
  def simple(value)
    "simple-#{value}"
  end
end

begin
  Object.send(:remove_const, :RactorDispatchFixture)
rescue NameError
end
class RactorDispatchFixture
  def value(n)
    n * 2
  end
end

begin
  Object.send(:remove_const, :RefinementFixture)
rescue NameError
end
class RefinementFixture
  def greet(name)
    "hello-#{name}"
  end
end

# Refinement defined at top-level so it can be `using`-ed from a
# nested module scope inside the example below.
module RefinementFixtureRefinement
  refine RefinementFixture do
    def greet(name)
      "refined-#{name}"
    end
  end
end

RSpec.describe 'Method probe dispatch semantics' do
  di_test

  let(:observed) { [] }
  let(:propagate_all_exceptions) { true }

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation).to receive_messages(
      enabled: true,
      max_capture_depth: 2,
      max_capture_attribute_count: 2,
      max_capture_string_length: 100,
      redacted_type_names: [],
      redacted_identifiers: [],
      redaction_excluded_identifiers: [],
    )
    allow(settings.dynamic_instrumentation.internal).to receive_messages(
      untargeted_trace_points: false,
      propagate_all_exceptions: propagate_all_exceptions,
      max_processing_time: 1,
    )
  end

  let(:redactor) { Datadog::DI::Redactor.new(settings) }
  let(:serializer) { Datadog::DI::Serializer.new(settings, redactor) }
  let(:logger) { instance_double(Logger, debug: nil) }
  let(:instrumenter) { Datadog::DI::Instrumenter.new(settings, serializer, logger, code_tracker: nil) }

  def install_probe(type_name, method_name, &on_fire)
    probe = Datadog::DI::Probe.new(
      id: 'method-probe-dispatch-semantics-spec',
      type: :log,
      type_name: type_name,
      method_name: method_name,
      capture_snapshot: false,
    )
    responder = Datadog::DI::ProcResponder.new(on_fire)
    instrumenter.hook_method(probe, responder)
    probe
  end

  describe 'fiber switches inside the probed method body' do
    # The method-probe wrapper is invoked on the fiber that calls the
    # probed method. During the method's execution, that fiber may
    # invoke Fiber.yield, which transfers control back to whichever
    # fiber called Fiber#resume. When the original fiber is resumed
    # the wrapper's post-super work runs (snapshot build, responder
    # callback). The assertions below pin down what must hold across
    # that round trip.

    after { instrumenter.unhook(probe) if probe }

    let!(:probe) do
      install_probe('FiberDispatchFixture', 'yield_then_return') do |context|
        observed << context
      end
    end

    it 'fires the probe exactly once per call when the body yields and resumes' do
      fixture = FiberDispatchFixture.new
      fiber = Fiber.new { fixture.yield_then_return('A') }
      yielded = fiber.resume
      expect(yielded).to eq('A')
      # At this point the probed method is paused mid-body. The wrapper
      # has not run its post-super hook yet because super has not returned.
      expect(observed.length).to eq 0

      returned = fiber.resume
      expect(returned).to eq('returned-A')
      # Once the body returns, the wrapper's post-super hook runs.
      expect(observed.length).to eq 1
      expect(observed.first.return_value).to eq('returned-A')
    end

    it 'isolates probe firings between concurrently-paused fibers' do
      fixture = FiberDispatchFixture.new
      fiber_x = Fiber.new { fixture.yield_then_return('X') }
      fiber_y = Fiber.new { fixture.yield_then_return('Y') }

      # Resume fiber_x — it enters the probed method, yields 'X' back.
      expect(fiber_x.resume).to eq('X')
      # Resume fiber_y — it independently enters the probed method,
      # yields 'Y' back. fiber_x's in-progress probe state must not
      # interfere with fiber_y's probe state.
      expect(fiber_y.resume).to eq('Y')

      # No firings yet — neither method has returned.
      expect(observed.length).to eq 0

      # Resume each fiber to completion. Each returns from its own
      # call; each fires the probe exactly once.
      expect(fiber_x.resume).to eq('returned-X')
      expect(fiber_y.resume).to eq('returned-Y')

      expect(observed.length).to eq 2
      return_values = observed.map(&:return_value)
      expect(return_values).to contain_exactly('returned-X', 'returned-Y')

      # The fixture method body increments resumed_count once on first
      # entry of each fiber. Both fibers entered the body, so the count
      # is 2. (Verifies that the wrapper did not re-enter the body on
      # the resume.)
      expect(fixture.resumed_count).to eq 2
    end

    it 'fires the probe for a non-yielding probed call made inside a fiber' do
      # A probed method that does NOT yield, invoked inside a fiber,
      # behaves identically to the same call on the main fiber. Pins
      # that the wrapper does not have a fiber-specific code path
      # that diverges for non-yielding methods.
      simple_probe = install_probe('FiberDispatchFixture', 'simple') do |context|
        observed << context
      end
      begin
        fixture = FiberDispatchFixture.new
        fiber = Fiber.new { fixture.simple(:inside) }
        expect(fiber.resume).to eq('simple-inside')
        expect(observed.map(&:return_value)).to include('simple-inside')
      ensure
        instrumenter.unhook(simple_probe)
      end
    end

    it 'preserves the customer method return value across a yield/resume cycle' do
      # Pins the contract that the wrapper's post-super hook does not
      # corrupt the return value when the body yielded and resumed
      # during execution.
      fixture = FiberDispatchFixture.new
      fiber = Fiber.new { fixture.yield_then_return('Z') }
      fiber.resume # yield point — discards yielded value
      final = fiber.resume
      expect(final).to eq('returned-Z')
      expect(observed.first.return_value).to eq('returned-Z')
    end

    it 'releases the fiber-local probe state when a fiber yields away mid-probe and is discarded' do
      # The wrapper sets up state (timing, args, context) before super.
      # If the fiber is abandoned while paused inside super, that state
      # is held only by the fiber's locals — it must not leak into any
      # later probe firing on the parent fiber.
      fixture = FiberDispatchFixture.new
      fiber = Fiber.new { fixture.yield_then_return('orphan') }
      yielded = fiber.resume
      expect(yielded).to eq('orphan')

      # Abandon the fiber by dropping the local-variable reference so the
      # subsequent GC.start can actually collect it. StandardRB flags the
      # assignment as useless because the variable is never read again,
      # but the dead-store is the entire point — it's what makes the fiber
      # collectable.
      fiber = nil # standard:disable Lint/UselessAssignment
      GC.start

      # A subsequent firing on the parent fiber should produce a
      # snapshot only for that call, not be polluted by the abandoned
      # fiber's in-progress state.
      observed.clear
      complete_fiber = Fiber.new { fixture.yield_then_return('completing') }
      expect(complete_fiber.resume).to eq('completing')
      expect(complete_fiber.resume).to eq('returned-completing')
      expect(observed.length).to eq 1
      expect(observed.first.return_value).to eq('returned-completing')
    end
  end

  describe 'Ractor isolation when invoking a probed method', ractors: true do
    # Ractors enforce that user-defined Ruby objects passed across
    # Ractor boundaries are either shareable (frozen / built-in / Ractor.make_shareable
    # processed) or accessed via copy. The method-probe wrapper closes over
    # an Instrumenter instance, which holds a Logger, settings, a serializer,
    # and a code tracker — none of which are Ractor-shareable.
    #
    # This describe block pins the observable behavior of calling a
    # probed method inside a non-main Ractor. The expectation is that
    # the wrapper's reference to the captured Instrumenter raises a
    # Ractor::IsolationError (or equivalent) when the closure body
    # tries to invoke instrumenter.* from the Ractor. Tests below do
    # not enforce a specific error class — they enforce that the
    # process does not crash and the error is communicable to the
    # main Ractor, so future changes either keep this property or
    # update the test deliberately.

    before do
      skip "Ractor requires Ruby 3.0+" if RUBY_VERSION < "3.0"
      # Ruby 3.0 Ractors have known bugs causing CI instability — matches the skip
      # pattern used in spec/datadog/profiling/native_extension_spec.rb.
      skip "Ruby 3.0 Ractors are too buggy to run this spec" if RUBY_VERSION.start_with?("3.0.")
    end

    after { instrumenter.unhook(probe) if probe }

    let!(:probe) do
      install_probe('RactorDispatchFixture', 'value') do |context|
        observed << context
      end
    end

    it 'does not crash the VM when a probed method is invoked from a non-main Ractor' do
      # The Ractor body invokes the probed method. The wrapper closure
      # captures non-shareable state; invoking it from inside the Ractor
      # must produce a Ruby-level error (any kind), not a VM crash.
      result = nil
      error_class = nil
      begin
        # Suppress Ractor experimental-warning noise on Ruby 3.x.
        verbose_was = $VERBOSE
        $VERBOSE = nil
        ractor = Ractor.new do
          RactorDispatchFixture.new.value(21)
        rescue => e
          [:error, e.class.name, e.message]
        else
          [:ok, nil, nil]
        end
        # Ractor#take was replaced by Ractor#value in Ruby 4.0; matches the
        # version-conditional pattern from spec/datadog/profiling/native_extension_spec.rb.
        result = (RUBY_VERSION < "4") ? ractor.take : ractor.value
        error_class = result[1]
      ensure
        $VERBOSE = verbose_was
      end

      # Either the Ractor returns a captured error (most likely
      # Ractor::IsolationError or Ractor::UnsafeError around the
      # captured Instrumenter / Logger), or it succeeds because Ruby
      # decided the closure was shareable enough. Both outcomes are
      # acceptable — what we pin is that the process did not crash
      # and the outcome was communicable to the main Ractor.
      expect([:ok, :error]).to include(result[0])
      if result[0] == :error
        expect(error_class).to be_a(String)
        expect(error_class).not_to be_empty
      end
    end

    it 'does not fire the probe on the main Ractor when the call is made inside a non-main Ractor' do
      # If the wrapper raises before super, the responder callback
      # should never run. If the wrapper succeeds (with shareable
      # state somehow), the responder may run inside the Ractor —
      # but it would not append to the main Ractor's `observed`
      # array (which is not shareable into the Ractor). Either way,
      # the main Ractor's `observed` is empty.
      verbose_was = $VERBOSE
      $VERBOSE = nil
      begin
        ractor = Ractor.new do
          RactorDispatchFixture.new.value(7)
          :ok
        rescue
          :error
        end
        (RUBY_VERSION < "4") ? ractor.take : ractor.value
      ensure
        $VERBOSE = verbose_was
      end

      expect(observed).to be_empty
    end

    it 'fires the probe normally on the main Ractor after a non-main-Ractor call has been attempted' do
      # A non-main-Ractor call may have left some intermediate wrapper
      # state behind (e.g., the wrapper began before raising). The
      # next call from the main Ractor must still be a complete probe
      # firing — no residual short-circuit from the failed Ractor
      # invocation.
      verbose_was = $VERBOSE
      $VERBOSE = nil
      begin
        ractor = Ractor.new do
          RactorDispatchFixture.new.value(7)
        rescue
          nil
        end
        (RUBY_VERSION < "4") ? ractor.take : ractor.value
      ensure
        $VERBOSE = verbose_was
      end

      RactorDispatchFixture.new.value(11)
      expect(observed.length).to eq 1
      expect(observed.first.return_value).to eq 22
    end
  end

  describe 'refinements visibility through the probe wrapper' do
    # A method-probe wrapper is installed via Module#prepend on the
    # target class. Refinements live in a separate dispatch namespace:
    # they are looked up on every method invocation inside a `using`
    # scope, before normal method lookup. Prepended modules sit at
    # the front of the class's ancestors chain, so:
    #
    #   - Outside `using`: customer call → wrapper (prepended) → original method.
    #   - Inside `using`: customer call → refined method (refinement lookup wins).
    #
    # The expected consequence is that probes installed on a class
    # method do NOT fire when the customer calls the method from inside
    # a `using` scope that refines that method, because refinement
    # dispatch bypasses the prepend chain. This describe block pins
    # that contract; if a future wrapper redesign makes refinements
    # interact with the probe wrapper differently, the test will
    # surface it deliberately rather than as a silent regression.

    after { instrumenter.unhook(probe) if probe }

    let!(:probe) do
      install_probe('RefinementFixture', 'greet') do |context|
        observed << context
      end
    end

    it 'fires the probe when the method is called outside any `using` scope' do
      result = RefinementFixture.new.greet('world')
      expect(result).to eq('hello-world')
      expect(observed.length).to eq 1
      expect(observed.first.return_value).to eq('hello-world')
    end

    it 'does not fire the probe when the method is called from inside a `using` scope that refines it' do
      # Refinements must be activated lexically. Define a fresh module,
      # `using` the refinement inside it, and call the method from a
      # method on that module. Refinement dispatch wins over the
      # prepended wrapper, so the probe does not fire.
      mod = Module.new do
        using RefinementFixtureRefinement

        def self.call_refined(fixture)
          fixture.greet('world')
        end
      end

      result = mod.call_refined(RefinementFixture.new)
      expect(result).to eq('refined-world')
      expect(observed).to be_empty
    end

    it 'fires the probe for callers outside the `using` scope even after another caller inside the scope did not fire' do
      # Pins the contract that an in-scope refinement call does not
      # disable the wrapper for out-of-scope callers. The probe state
      # is unchanged by the refined call (because the wrapper was
      # never invoked).
      mod = Module.new do
        using RefinementFixtureRefinement

        def self.call_refined(fixture)
          fixture.greet('world')
        end
      end

      mod.call_refined(RefinementFixture.new)
      expect(observed).to be_empty

      result = RefinementFixture.new.greet('world')
      expect(result).to eq('hello-world')
      expect(observed.length).to eq 1
      expect(observed.first.return_value).to eq('hello-world')
    end
  end
end
