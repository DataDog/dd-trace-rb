# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di/logger"
require "logger"

RSpec.describe Datadog::DI::Logger do
  # A real ::Logger writing to an in-memory buffer so debug calls are
  # observable without stubbing the target.
  let(:target) do
    ::Logger.new(io)
  end

  let(:io) do
    StringIO.new
  end

  let(:trace_logging) { true }

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation.internal).to receive(:trace_logging).and_return(trace_logging)
  end

  subject(:logger) do
    described_class.new(settings, target)
  end

  describe "#debug" do
    context "when called with a block" do
      it "delegates to the target logger at debug level" do
        expect(target).to receive(:debug) do |&block|
          expect(block.call).to eq("di: hello")
        end

        logger.debug { "di: hello" }
      end

      it "writes the block's message to the target's output" do
        logger.debug { "di: hello" }

        expect(io.string).to include("di: hello")
      end
    end

    context "when called with a message argument" do
      it "delegates the message to the target logger" do
        expect(target).to receive(:debug).with("di: hello")

        logger.debug("di: hello")
      end

      it "writes the message to the target's output" do
        logger.debug("di: hello")

        expect(io.string).to include("di: hello")
      end
    end

    it "returns nil on both forms" do
      expect(logger.debug { "di: hello" }).to be_nil
      expect(logger.debug("di: hello")).to be_nil
    end
  end

  describe "#trace" do
    context "when trace logging is enabled" do
      let(:trace_logging) { true }

      it "delegates to the target logger at debug level" do
        expect(target).to receive(:debug) do |&block|
          expect(block.call).to eq("di: hello")
        end

        logger.trace { "di: hello" }
      end

      it "returns nil" do
        expect(logger.trace { "di: hello" }).to be_nil
      end

      it "writes the message to the target's output" do
        logger.trace { "di: hello" }

        expect(io.string).to include("di: hello")
      end
    end

    context "when trace logging is disabled" do
      let(:trace_logging) { false }

      it "does not invoke the target logger and returns nil" do
        expect(target).not_to receive(:debug)

        expect(logger.trace { "di: hello" }).to be_nil
      end

      it "does not invoke the block" do
        # If the block were materialized and called, this would raise.
        # The block is never invoked when trace logging is off, so the
        # side effect never fires.
        expect do
          logger.trace { raise "block must not be invoked when trace logging is off" }
        end.not_to raise_error
      end

      it "writes nothing to the target's output" do
        logger.trace { "di: hello" }

        expect(io.string).to be_empty
      end
    end
  end

  describe "the trace-logging gate" do
    it "resolves the gate once at construction" do
      logger

      allow(settings.dynamic_instrumentation.internal).to receive(:trace_logging).and_return(false)

      expect(target).to receive(:debug)
      logger.trace { "di: hello" }
    end
  end
end
