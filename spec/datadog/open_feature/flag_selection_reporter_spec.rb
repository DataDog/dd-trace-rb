# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/flag_selection_reporter"

RSpec.describe Datadog::OpenFeature::FlagSelectionReporter do
  subject(:reporter) { described_class.new(logger: logger, telemetry: telemetry) }

  let(:logger) { instance_double(Datadog::Core::Logger, error: nil, warn: nil, debug: nil) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, inc: nil) }

  before { described_class.reset_once_guards }
  after { described_class.reset_once_guards }

  describe "#report_dropped" do
    {
      "malformed_selection" => "flag_selection must be a Hash with optional tags and key_patterns string arrays",
      "too_many_values" => "each list accepts at most 31 values",
      "invalid_key_pattern" => "each key pattern is at most 200 UTF-8 bytes",
      "invalid_tag" => "each tag is at most 200 UTF-8 bytes",
    }.each do |reason, limit|
      it "logs #{reason} with its limit" do
        reporter.report_dropped(reason)

        expect(logger).to have_received(:error)
          .with("flag_selection was not sent (#{reason}: #{limit}). Loading the full flag configuration.")
        expect(telemetry).to have_received(:inc)
          .with("tracers", "flag_selection.dropped", 1, tags: {reason: reason})
      end
    end

    it "logs every call and counts each reason once per process" do
      2.times { reporter.report_dropped("invalid_tag") }
      described_class.new(logger: logger, telemetry: telemetry).report_dropped("invalid_tag")
      reporter.report_dropped("too_many_values")

      expect(logger).to have_received(:error).with(a_string_including("(invalid_tag:")).exactly(3).times
      expect(telemetry).to have_received(:inc)
        .with("tracers", "flag_selection.dropped", 1, tags: {reason: "invalid_tag"}).once
      expect(telemetry).to have_received(:inc)
        .with("tracers", "flag_selection.dropped", 1, tags: {reason: "too_many_values"}).once
    end
  end

  describe "#count_dropped" do
    it "counts once per process per reason without logging, sharing the count with #report_dropped" do
      2.times { reporter.count_dropped("invalid_tag") }
      reporter.report_dropped("invalid_tag")

      expect(logger).to have_received(:error).once
      expect(telemetry).to have_received(:inc)
        .with("tracers", "flag_selection.dropped", 1, tags: {reason: "invalid_tag"}).once
    end
  end

  describe "#report_url_too_long" do
    it "logs too_many_values with the URL limit and shares its count" do
      reporter.report_url_too_long
      reporter.report_dropped("too_many_values")

      expect(logger).to have_received(:error).with(
        "flag_selection was not sent (too_many_values: the request URL is at most 8192 bytes). " \
          "Loading the full flag configuration.",
      )
      expect(telemetry).to have_received(:inc)
        .with("tracers", "flag_selection.dropped", 1, tags: {reason: "too_many_values"}).once
    end
  end

  describe "#report_ignored" do
    %w[malformed_selection too_many_values invalid_key_pattern invalid_tag tag_load_failed].each do |reason|
      it "logs and counts the known reason #{reason}" do
        reporter.report_ignored(reason.b)

        expect(logger).to have_received(:error)
          .with("flag_selection was ignored by the server (#{reason}). Loaded the full flag configuration.")
        expect(telemetry).to have_received(:inc)
          .with("tracers", "flag_selection.ignored", 1, tags: {reason: reason})
      end
    end

    [
      "tag_load_failed ",
      " tag_load_failed",
      "TAG_LOAD_FAILED",
      "invalid_tag, invalid_tag",
      "team:payments",
      "a" * 33,
      "tag_load_failed".encode(Encoding::UTF_16LE),
    ].each do |value|
      it "logs and counts #{value.inspect} as unknown" do
        reporter.report_ignored(value)

        expect(logger).to have_received(:error)
          .with("flag_selection was ignored by the server (unknown). Loaded the full flag configuration.")
        expect(telemetry).to have_received(:inc)
          .with("tracers", "flag_selection.ignored", 1, tags: {reason: "unknown"})
      end
    end

    [nil, ""].each do |value|
      it "treats #{value.inspect} as absent" do
        reporter.report_ignored(value)

        expect(logger).not_to have_received(:error)
        expect(telemetry).not_to have_received(:inc)
      end
    end

    it "logs and counts each reason once per process" do
      2.times { reporter.report_ignored("invalid_tag") }
      described_class.new(logger: logger, telemetry: telemetry).report_ignored("invalid_tag")
      reporter.report_ignored("bogus")
      reporter.report_ignored("other")

      expect(logger).to have_received(:error).with(a_string_including("(invalid_tag)")).once
      expect(logger).to have_received(:error).with(a_string_including("(unknown)")).once
      expect(telemetry).to have_received(:inc).twice
    end
  end

  describe "#warn_selection_differs" do
    it "warns once per process" do
      2.times { reporter.warn_selection_differs }
      described_class.new(logger: logger, telemetry: telemetry).warn_selection_differs

      expect(logger).to have_received(:warn).with(
        "flag_selection differs from the flag selection already in use in this process. Using the first selection.",
      ).once
      expect(telemetry).not_to have_received(:inc)
    end
  end

  describe "#warn_remote_config" do
    it "warns once per process" do
      2.times { reporter.warn_remote_config }

      expect(logger).to have_received(:warn).with(
        "flag_selection is not supported when flags are delivered through Remote Config. " \
          "Loading the full flag configuration.",
      ).once
      expect(telemetry).not_to have_received(:inc)
    end
  end

  describe ".reset_once_guards" do
    it "lets every once-per-process report happen again" do
      reporter.report_dropped("invalid_tag")
      reporter.report_ignored("invalid_tag")
      reporter.warn_selection_differs
      reporter.warn_remote_config

      described_class.reset_once_guards
      reporter.report_dropped("invalid_tag")
      reporter.report_ignored("invalid_tag")
      reporter.warn_selection_differs
      reporter.warn_remote_config

      expect(telemetry).to have_received(:inc).exactly(4).times
      expect(logger).to have_received(:error).with(a_string_including("ignored by the server")).twice
      expect(logger).to have_received(:warn).exactly(4).times
    end
  end

  context "when telemetry raises" do
    before { allow(telemetry).to receive(:inc).and_raise(StandardError, "telemetry failed") }

    it "does not raise into the caller" do
      expect { reporter.report_dropped("invalid_tag") }.not_to raise_error
      expect { reporter.report_ignored("invalid_tag") }.not_to raise_error
      expect(logger).to have_received(:error).twice
    end
  end
end
