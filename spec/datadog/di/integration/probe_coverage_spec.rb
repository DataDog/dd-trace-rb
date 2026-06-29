require 'datadog/di/spec_helper'
require 'datadog/di'

# The line-probe pre-load case is the one that historically did not
# work in Ruby DI: a customer who created a line probe in the Datadog
# UI for a file already loaded into the process (typically the
# customer's own application code, loaded before the tracer enabled
# DI) would see the probe silently never fire. The fix is two parts
# already on the enablement branch: (a) backfill_registry runs at
# code-tracking activation so pre-loaded iseqs are registered, and
# (b) DI.activate_tracking is invoked by handle_rc_enablement on the
# RC enable signal — so a customer's late-loaded code path is also
# covered.
#
# Method probes use Module#prepend, which is unaffected by code-
# tracking timing. They serve as regression coverage: both rows of
# the load-before / load-after matrix must continue to pass.
#
# Each matrix cell uses its own fixture file and class name. Reusing
# a class name across cases would force a remove_const-then-redefine
# pattern that leaks stale Class / iseq objects into ObjectSpace and
# couples this spec to the same CRuby Module#name cache behavior that
# PR #5872 addresses for SymDB.

RSpec.describe 'DI probe coverage across enablement timing' do
  di_test

  let(:diagnostics_transport) do
    instance_double(Datadog::DI::Transport::Diagnostics::Transport).tap do |t|
      allow(t).to receive(:send_diagnostics)
    end
  end

  let(:input_transport) do
    instance_double(Datadog::DI::Transport::Input::Transport).tap do |t|
      allow(t).to receive(:send_input)
    end
  end

  before do
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.remote.enabled = true
      # Customer did NOT set DD_DYNAMIC_INSTRUMENTATION_ENABLED — the
      # component will be built in stopped state. Implicit enablement
      # via handle_rc_enablement is what starts it below.
      s.dynamic_instrumentation.internal.development = true
      s.dynamic_instrumentation.internal.propagate_all_exceptions = true
    end
  end

  let(:agent_settings) { instance_double_agent_settings }
  let(:logger) { logger_allowing_debug }

  let(:component) do
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |c|
      raise "Component failed to build — unsuitable environment? Check logs" if c.nil?
    end
  end

  let(:probe_manager) { component.probe_manager }

  def simulate_rc_enablement
    # Mirror what Tracing::Remote.process_config does on
    # `dynamic_instrumentation_enabled: true`. Bypassing the full Remote
    # plumbing here — the integration spec covers that path. This test
    # focuses on the post-enablement probe-install matrix.
    Datadog::DI.activate_tracking
    component.start!
  end

  before do
    # Each test starts from inactive code tracking so the pre-load case
    # is real. Tests don't share fixtures, so we don't need to
    # remove_const between tests.
    Datadog::DI.deactivate_tracking!
  end

  after do
    component.shutdown!
    Datadog::DI.deactivate_tracking!
  end

  describe 'line probe' do
    context 'code loaded BEFORE implicit enablement' do
      # The historically-broken case. With backfill_registry running at
      # activate_tracking time, the iseq for the target file is
      # recovered after the fact and the line probe installs and fires.

      let(:probe) do
        Datadog::DI::Probe.new(
          id: 'line-probe-21-pre',
          type: :log,
          file: 'probe_coverage_line_pre_target_class.rb',
          line_no: 13, # `answer = 42` in the pre-fixture
          capture_snapshot: false,
        )
      end

      it 'fires when the target line executes' do
        # 1. Code loaded — tracking NOT yet active.
        load File.join(File.dirname(__FILE__), 'probe_coverage_line_pre_target_class.rb')
        expect(Datadog::DI.code_tracking_active?).to be false

        # 2. RC enable signal — activates tracking (which backfills the
        #    registry from already-loaded iseqs) and starts the component.
        simulate_rc_enablement
        expect(Datadog::DI.code_tracking_active?).to be true

        # 3. Probe arrives via LIVE_DEBUGGING RC — installs against the
        #    backfilled iseq.
        probe_manager.add_probe(probe)
        component.probe_notifier_worker.flush
        expect(probe_manager.probe_repository.installed_probes).not_to be_empty

        # 4. Target line executes — probe fires.
        expect(component.probe_notifier_worker).to receive(:add_snapshot).at_least(:once)
        expect(ProbeCoverageLinePreTargetClass.new.target_method).to eq(42)
      end
    end

    context 'code loaded AFTER implicit enablement' do
      # The historically-working case. Code-tracking trace point captures
      # the iseq via :script_compiled as the file is loaded.

      let(:probe) do
        Datadog::DI::Probe.new(
          id: 'line-probe-21-post',
          type: :log,
          file: 'probe_coverage_line_post_target_class.rb',
          line_no: 10, # `answer = 42` in the post-fixture
          capture_snapshot: false,
        )
      end

      it 'fires when the target line executes' do
        # 1. RC enable signal — activates tracking, starts the component.
        simulate_rc_enablement
        expect(Datadog::DI.code_tracking_active?).to be true

        # 2. Customer code loaded after enablement — :script_compiled
        #    trace point captures it.
        load File.join(File.dirname(__FILE__), 'probe_coverage_line_post_target_class.rb')

        # 3. Probe arrives — installs.
        probe_manager.add_probe(probe)
        component.probe_notifier_worker.flush
        expect(probe_manager.probe_repository.installed_probes).not_to be_empty

        # 4. Target line executes — probe fires.
        expect(component.probe_notifier_worker).to receive(:add_snapshot).at_least(:once)
        expect(ProbeCoverageLinePostTargetClass.new.target_method).to eq(42)
      end
    end
  end

  describe 'method probe' do
    context 'code loaded BEFORE implicit enablement' do
      # Method probes use Module#prepend, which works regardless of
      # code-tracking timing. Regression coverage.

      let(:probe) do
        Datadog::DI::Probe.new(
          id: 'method-probe-22-pre',
          type: :log,
          type_name: 'ProbeCoverageMethodPreTargetClass',
          method_name: 'target_method',
          capture_snapshot: false,
        )
      end

      it 'fires when the target method is invoked' do
        load File.join(File.dirname(__FILE__), 'probe_coverage_method_pre_target_class.rb')
        simulate_rc_enablement

        probe_manager.add_probe(probe)
        component.probe_notifier_worker.flush
        expect(probe_manager.probe_repository.installed_probes).not_to be_empty

        expect(component.probe_notifier_worker).to receive(:add_snapshot).at_least(:once)
        expect(ProbeCoverageMethodPreTargetClass.new.target_method).to eq(42)
      end
    end

    context 'code loaded AFTER implicit enablement' do
      let(:probe) do
        Datadog::DI::Probe.new(
          id: 'method-probe-22-post',
          type: :log,
          type_name: 'ProbeCoverageMethodPostTargetClass',
          method_name: 'target_method',
          capture_snapshot: false,
        )
      end

      it 'fires when the target method is invoked' do
        simulate_rc_enablement
        load File.join(File.dirname(__FILE__), 'probe_coverage_method_post_target_class.rb')

        probe_manager.add_probe(probe)
        component.probe_notifier_worker.flush
        expect(probe_manager.probe_repository.installed_probes).not_to be_empty

        expect(component.probe_notifier_worker).to receive(:add_snapshot).at_least(:once)
        expect(ProbeCoverageMethodPostTargetClass.new.target_method).to eq(42)
      end
    end
  end
end
