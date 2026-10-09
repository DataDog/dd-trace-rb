require "datadog/di/spec_helper"
require "datadog/di"

RSpec.describe Datadog::DI do
  di_test

  describe ".active_trace" do
    context "with components and an active trace" do
      it "returns the active trace" do
        components = instance_double(Datadog::Core::Configuration::Components)
        tracer = instance_double(Datadog::Tracing::Tracer)
        trace = instance_double(Datadog::Tracing::TraceOperation)
        expect(Datadog).to receive(:components).with(allow_initialization: false).and_return(components)
        expect(components).to receive(:tracer).and_return(tracer)
        expect(tracer).to receive(:active_trace).and_return(trace)

        expect(described_class.active_trace).to equal(trace)
      end
    end

    context "with no components" do
      it "returns nil" do
        expect(Datadog).to receive(:components).with(allow_initialization: false).and_return(nil)

        expect(described_class.active_trace).to be_nil
      end
    end

    context "when Datadog::Tracing is not defined" do
      it "returns nil without looking up components" do
        hide_const("Datadog::Tracing")
        expect(Datadog).not_to receive(:components)

        expect(described_class.active_trace).to be_nil
      end
    end

    context "with a built component tree" do
      before do
        Datadog.configure {}
      end

      after do
        Datadog.send(:reset!)
      end

      it "returns the active trace" do
        Datadog::Tracing.trace("di active trace") do
          expect(described_class.active_trace).to equal(Datadog::Tracing.active_trace)
        end
      end
    end
  end
end
