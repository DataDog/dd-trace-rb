# frozen_string_literal: true

require "spec_helper"
require "opentelemetry/sdk"
require "datadog/opentelemetry"

RSpec.describe Datadog::OpenTelemetry::SDK::SpanProcessor do
  subject(:span_processor) { described_class.new }

  let(:writer) { double("writer") }

  before do
    allow(span_processor).to receive(:writer).and_return(writer)
  end

  describe "#force_flush" do
    subject(:force_flush) { span_processor.force_flush(timeout: 5) }

    context "when the writer supports force_flush" do
      before { allow(writer).to receive(:force_flush) }

      it "flushes the writer and returns SUCCESS" do
        is_expected.to be(::OpenTelemetry::SDK::Trace::Export::SUCCESS)
        expect(writer).to have_received(:force_flush).with(timeout: 5)
      end
    end

    context "when the writer does not support force_flush" do
      it { is_expected.to be(::OpenTelemetry::SDK::Trace::Export::SUCCESS) }
    end
  end

  describe "#shutdown" do
    subject(:shutdown) { span_processor.shutdown(timeout: 5) }

    before { allow(writer).to receive(:stop) }

    it "stops the writer and returns SUCCESS" do
      is_expected.to be(::OpenTelemetry::SDK::Trace::Export::SUCCESS)
      expect(writer).to have_received(:stop)
    end
  end
end
