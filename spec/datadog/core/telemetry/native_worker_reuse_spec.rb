# frozen_string_literal: true

require "spec_helper"

require "datadog/core/telemetry/component"

RSpec.describe "Native telemetry worker reuse across reconfigures" do
  let(:native_worker) { instance_double(Datadog::Core::Telemetry::Native::Worker) }
  let(:ruby_worker) { double(Datadog::Core::Telemetry::Worker) }
  let(:native_worker_class) do
    Class.new do
      def self._native_new(**_args)
        raise "stub me"
      end
    end
  end

  before do
    stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
    stub_const("Datadog::Core::Telemetry::Native::Worker", native_worker_class)
    allow(native_worker_class).to receive(:_native_new).and_return(native_worker)
    allow(native_worker).to receive(:_start)
    allow(native_worker).to receive(:_shutdown)
    allow(native_worker).to receive(:_register_metric_context).and_return(:context)
    allow(native_worker).to receive(:_add_point)
    allow(native_worker).to receive(:_add_log)
    allow(native_worker).to receive(:_add_config)
    allow(native_worker).to receive(:_add_dependency)
    allow(native_worker).to receive(:_add_integration)
    allow(native_worker).to receive(:_add_endpoint)

    allow(Datadog::Core::Telemetry::Worker).to receive(:new).and_return(ruby_worker)
    allow(ruby_worker).to receive(:start)
    allow(ruby_worker).to receive(:enqueue)
    allow(ruby_worker).to receive(:stop)
    allow(ruby_worker).to receive(:flush)
    allow(ruby_worker).to receive(:"enabled=")
    allow(ruby_worker).to receive(:after_fork_monkey_patched)
    allow(ruby_worker).to receive(:prepare_initial_event)

    Datadog.send(:reset!)
    Datadog.configure do |c|
      c.telemetry.enabled = true
      c.telemetry.native_worker = true
    end
  end

  after do
    Datadog.send(:reset!)
  end

  it "keeps one native worker across a reconfigure" do
    first = Datadog.send(:components).telemetry.backend.native_worker
    expect(native_worker_class).to have_received(:_native_new).once

    Datadog.configure do |c|
      c.telemetry.enabled = true
    end

    second = Datadog.send(:components).telemetry.backend.native_worker
    expect(second).to be(first)
    expect(native_worker_class).to have_received(:_native_new).once
    expect(native_worker).not_to have_received(:_shutdown)
  end
end
