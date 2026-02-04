require 'spec_helper'

RSpec.describe Datadog::Core::Telemetry::Component do
  before(:all) do
    if RUBY_VERSION < '2.6'
      # The tests here are flaking in CI on Ruby 2.5.
      # Once I add diagnostics to investigate why they are failing, they
      # stop failing.
      # After 3 weeks of trying to figure this out I am skipping
      # the failing runtimes.
      skip 'flaky in CI'
    end

    reset_at_fork_monkey_patch_for_components!
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.telemetry.enabled = true
      # Reduce the number of generated events
      settings.telemetry.dependency_collection = false
    end
  end

  let(:logger) { logger_allowing_debug }

  # Uncomment for debugging to see the log entries.
  #let(:logger) { Logger.new(STDERR) }

  let(:components) do
    Datadog::Core::Configuration::Components.new(settings)
  end

  let(:component) do
    components.telemetry
  end

  let(:agent_settings) do
    components.agent_settings
  end

  after do
    component.shutdown!
  end

  let(:initial_event) do
    double(Datadog::Core::Telemetry::Event::AppStarted,
      payload: {hello: 'world'},
      type: 'app-started',
      app_started?: true,)
  end

  let(:response) do
    double(Datadog::Core::Transport::HTTP::Response,
      ok?: true,)
  end

  let(:events) { [] }

  def assert_events(events)
    expect(events.length).to eq 2
    expect(events.first).to be initial_event
    expect(events[1]).to be_a(Datadog::Core::Telemetry::Event::MessageBatch)
    expect(events[1].events.length).to eq 1
    metrics_event = events[1].events.first
    expect(metrics_event).to be_a(Datadog::Core::Telemetry::Event::GenerateMetrics)
    expect(metrics_event.payload).to match(
      namespace: 'ns',
      series: [
        metric: 'hello',
        points: [[Integer, 1]],
        type: 'count',
        tags: [],
        common: true,
      ],
    )
  end

  context 'when worker is started before metrics are submitted' do
    it 'emits metrics' do
      expect(Datadog::Core::Telemetry::Event::AppStarted).to receive(:new).and_return(initial_event)
      expect(component.worker).to receive(:send_event).twice do |event|
        events << event
        response
      end.ordered
      component.start(components: components)
      component.inc('ns', 'hello', 1)
      # Assert that the flush succeeded, because we were sometimes not
      # getting both of the events.
      expect(component.flush).to be true

      assert_events(events)
    end
  end

  context 'when metrics are submitted before worker is started' do
    it 'emits metrics' do
      expect(Datadog::Core::Telemetry::Event::AppStarted).to receive(:new).and_return(initial_event)
      expect(component.worker).to receive(:send_event).twice do |event|
        events << event
        response
      end.ordered
      component.inc('ns', 'hello', 1)
      expect(component.worker.running?).to be false
      component.start(components: components)
      # Assert that the flush succeeded, because we were sometimes not
      # getting both of the events.
      expect(component.flush).to be true

      assert_events(events)
    end

    # Submitting metrics in parent with the worker running is racy - we
    # don't know if the worker in the parent will flush the events before
    # the fork executes.
    # Only test the forking case when worker is started after the fork
    # (in the forked child).
    context 'in forked child' do
      forking_platform_only

      before do
        # after_fork handler goes through the global variable.
        expect(Datadog).to receive(:components).at_least(:once).and_return(components)
      end

      it 'emits child but not parent metrics' do
        expect(Datadog::Core::Telemetry::Event::AppStarted).to receive(:new).and_return(initial_event)
        expect(component.worker).to receive(:send_event).twice do |event|
          events << event
          response
        end.ordered
        component.inc('ns', 'hello', 1)
        expect(component.worker.running?).to be false

        expect(component.metrics_manager.collections.keys).to eq(%w[ns])

        # The timeout for each flush is 15 seconds, and we perform two
        # flushes. Thus the total timeout needs to be at least 30 seconds.
        expect_in_fork(timeout_seconds: 40) do
          # We expect namespaces to have been reset.
          expect(component.metrics_manager.collections).to be_empty

          component.inc('child-ns', 'child-metric', 1)
          expect(component.worker.running?).to be false

          # We expect only child namespace to be present.
          expect(component.metrics_manager.collections.keys).to eq(%w[child-ns])

          component.start(components: components)
          expect(component.flush).to be true

          expect(events.length).to eq 2
          # We are going to have an initial event in the child
          expect(events.first).to be initial_event
          expect(events[1]).to be_a(Datadog::Core::Telemetry::Event::MessageBatch)
          expect(events[1].events.length).to eq 1
          metrics_event = events[1].events.first
          expect(metrics_event).to be_a(Datadog::Core::Telemetry::Event::GenerateMetrics)
          expect(metrics_event.payload).to match(
            namespace: 'child-ns',
            series: [
              # Child only - no parent metric sent.
              metric: 'child-metric',
              points: [[Integer, 1]],
              type: 'count',
              tags: [],
              common: true,
            ],
          )
        end

        # The events added in the parent should be sent in the parent.
        # We still haven't started the worker in parent - do so now.
        component.start(components: components)
        # Assert that the flush succeeded, because we were sometimes not
        # getting both of the events.
        expect(component.flush).to be true
        assert_events(events)
      end
    end
  end
end
