# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "datadog/open_feature/exposures/reporter"

RSpec.describe Datadog::OpenFeature::Exposures::Reporter do
  subject(:reporter) do
    described_class.new(
      worker, telemetry: telemetry, logger: logger, datadog_logging_enabled: datadog_logging_enabled,
    )
  end

  let(:debug_messages) { [] }
  let(:worker) { instance_double(Datadog::OpenFeature::Exposures::Worker) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil, debug?: true) }
  let(:datadog_logging_enabled) { true }
  let(:context) { OpenFeature::SDK::EvaluationContext.new(targeting_key: "john-doe") }
  let(:features) { {} }

  before do
    allow(logger).to receive(:debug) do |message, &block|
      debug_messages << (block ? block.call : message) if logger.debug?
    end
  end

  def record(variant: "4", serial_id: nil, targeting_key: "john-doe")
    reporter.record(
      flag_key: "feature_flag", allocation_key: "4-for-john-doe", variant: variant, serial_id: serial_id,
      context: OpenFeature::SDK::EvaluationContext.new(targeting_key: targeting_key), features: features,
    )
  end

  describe "#record" do
    context "when the exposure is new" do
      it "enqueues the event and reports no cache hit" do
        expect(worker).to receive(:enqueue).with(
          hash_including(flag: {key: "feature_flag"}, variant: {key: "4"}, subject: hash_including(id: "john-doe")),
        ).and_return(true)

        expect(record).to be(false)
      end

      it "logs the queued exposure" do
        allow(worker).to receive(:enqueue).and_return(true)

        record

        expect(debug_messages).to include(
          'Feature Flags: queued exposure for "feature_flag" (allocation="4-for-john-doe", variant="4", ' \
            'targeting_key="john-doe")',
        )
      end

      it "does not claim a rejected exposure was queued" do
        allow(worker).to receive(:enqueue).and_return(false)

        expect(record).to be(false)
        expect(debug_messages).to be_empty
      end
    end

    context "when exposure features are given" do
      let(:features) { {"holdout.key" => "h-1"} }

      it "puts them on the event" do
        expect(worker).to receive(:enqueue).with(hash_including(features: {"holdout.key" => "h-1"})).and_return(true)

        record
      end
    end

    context "when the same exposure repeats" do
      before { allow(worker).to receive(:enqueue).and_return(true) }

      it "reports a cache hit and does not enqueue again" do
        expect(record).to be(false)
        expect(record).to be(true)
        expect(worker).to have_received(:enqueue).once
      end

      it "logs why the exposure was not sent" do
        record
        record

        expect(debug_messages).to include(
          'Feature Flags: exposure for "feature_flag" not sent: duplicate of the last exposure for this subject',
        )
      end
    end

    context "when the variant changes" do
      before { allow(worker).to receive(:enqueue).and_return(true) }

      it "is a new exposure" do
        expect(record(variant: "4")).to be(false)
        expect(record(variant: "5")).to be(false)
        expect(worker).to have_received(:enqueue).twice
      end
    end

    context "when the serial id changes" do
      before { allow(worker).to receive(:enqueue).and_return(true) }

      it "is a new exposure, including a serial id appearing" do
        expect(record(serial_id: nil)).to be(false)
        expect(record(serial_id: 0)).to be(false)
        expect(record(serial_id: 1)).to be(false)
        expect(record(serial_id: 1)).to be(true)
        expect(worker).to have_received(:enqueue).exactly(3).times
      end
    end

    context "when another subject is exposed" do
      before { allow(worker).to receive(:enqueue).and_return(true) }

      it "is a new exposure" do
        expect(record(targeting_key: "john-doe")).to be(false)
        expect(record(targeting_key: "jane-doe")).to be(false)
      end
    end

    context "when Datadog exposure logging is disabled" do
      let(:datadog_logging_enabled) { false }

      it "sends nothing but still records the exposure" do
        expect(worker).not_to receive(:enqueue)

        expect(record).to be(false)
        expect(record).to be(true)
      end

      it "logs why the exposure was not sent" do
        record

        expect(debug_messages).to include(
          'Feature Flags: exposure for "feature_flag" not sent: Datadog exposure logging is disabled',
        )
      end
    end
  end
end
