# frozen_string_literal: true

require "spec_helper"
require "opentelemetry/sdk"
require "datadog/opentelemetry"

RSpec.describe Datadog::OpenTelemetry::SDK::Propagator do
  describe "#inject" do
    subject(:inject) { propagator.inject({}) }

    let(:propagator) { described_class.new(datadog_propagator) }
    let(:datadog_propagator) { double("datadog_propagator") }

    before { allow(datadog_propagator).to receive(:inject) }

    context "when there is no active trace" do
      # ::OpenTelemetry::Context.current returns ROOT, whose #trace is nil.
      it "does not raise or inject" do
        expect { inject }.not_to raise_error
        expect(datadog_propagator).not_to have_received(:inject)
      end
    end

    context "when the context has an active trace" do
      it "injects the trace digest" do
        trace = Datadog::Tracing.send(:tracer).send(:start_trace)
        context = ::OpenTelemetry::Context.from_trace(trace)
        propagator.inject({}, context: context)

        expect(datadog_propagator).to have_received(:inject).with(instance_of(Datadog::Tracing::TraceDigest), {})
      end
    end
  end
end
