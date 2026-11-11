require "datadog/di/spec_helper"
require "datadog/di"

RSpec.describe Datadog::DI do
  di_test

  # The probe-path trace and span reads share one lookup contract: the
  # read skips component-tree initialization, and the read is nil when
  # tracing is absent.
  shared_examples "a non-initializing active read" do |read|
    context "with components" do
      it "returns the tracer's value" do
        components = instance_double(Datadog::Core::Configuration::Components)
        tracer = instance_double(Datadog::Tracing::Tracer)
        value = Object.new
        expect(Datadog).to receive(:components).with(allow_initialization: false).and_return(components)
        expect(components).to receive(:tracer).and_return(tracer)
        expect(tracer).to receive(read).and_return(value)

        expect(described_class.public_send(read)).to equal(value)
      end
    end

    context "with no components" do
      it "returns nil" do
        expect(Datadog).to receive(:components).with(allow_initialization: false).and_return(nil)

        expect(described_class.public_send(read)).to be_nil
      end
    end

    context "when Datadog::Tracing is not defined" do
      it "returns nil without looking up components" do
        hide_const("Datadog::Tracing")
        expect(Datadog).not_to receive(:components)

        expect(described_class.public_send(read)).to be_nil
      end
    end

    context "with a built component tree" do
      before do
        Datadog.configure {}
      end

      after do
        Datadog.send(:reset!)
      end

      it "returns the tracing module's value" do
        Datadog::Tracing.trace("di active read") do
          expect(described_class.public_send(read)).to equal(Datadog::Tracing.public_send(read))
        end
      end
    end
  end

  describe ".active_trace" do
    include_examples "a non-initializing active read", :active_trace
  end

  describe ".active_span" do
    include_examples "a non-initializing active read", :active_span
  end
end
