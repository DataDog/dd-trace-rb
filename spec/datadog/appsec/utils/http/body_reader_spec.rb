# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/utils/http/body_reader"

require "stringio"

RSpec.describe Datadog::AppSec::Utils::HTTP::BodyReader do
  describe ".read" do
    context "when body is nil" do
      let(:buffer) { described_class.read(nil, limit: 9) }

      it { expect(buffer).to be_nil }
    end

    context "when body is unsupported" do
      let(:buffer) { described_class.read(Object.new, limit: 9) }

      it { expect(buffer).to be_nil }
    end

    context "when String body fits within the limit" do
      let(:buffer) { described_class.read("name=joe", limit: 9) }

      it { expect(buffer).to eq("name=joe") }
    end

    context "when String body size is exactly the limit" do
      let(:buffer) { described_class.read("name=john", limit: 9) }

      it { expect(buffer).to eq("name=john") }
    end

    context "when String body is one byte over the limit" do
      let(:buffer) { described_class.read("name=john!", limit: 9) }

      it { expect(buffer).to eq("name=john!") }
    end

    context "when String body exceeds the limit" do
      let(:buffer) { described_class.read("name=john&role=admin", limit: 9) }

      it { expect(buffer).to eq("name=john&") }
    end

    context "when body is a forward-only reader and rewind is required" do
      before { allow(body).to receive(:read).and_return("name=john", nil) }

      let(:buffer) { described_class.read(body, limit: 9, rewind_before_read: true) }
      let(:body) { double("body") }

      it { expect(buffer).to be_nil }
    end
  end

  describe ".read_stream" do
    context "when body is a rewindable IO and rewinding is enabled" do
      let(:buffer) { described_class.read_stream(body, limit: 9, rewind_before_read: true) }
      let(:body) { StringIO.new("name=john") }

      it "returns the body and keeps it readable" do
        expect(buffer).to eq("name=john")
        expect(body.read).to eq("name=john")
      end
    end

    context "when body is a rewindable IO and rewinding is not enabled" do
      before { allow(body).to receive(:rewind).and_call_original }

      let(:buffer) { described_class.read_stream(body, limit: 9) }
      let(:body) { StringIO.new("name=john") }

      it "returns the body without rewinding" do
        expect(buffer).to eq("name=john")
        expect(body).not_to have_received(:rewind)
      end
    end

    context "when body is a rewindable IO, exceeds the limit, and rewinding is enabled" do
      let(:buffer) { described_class.read_stream(body, limit: 9, rewind_before_read: true) }
      let(:body) { StringIO.new("name=john&role=admin") }

      it "returns one byte over the limit and keeps the body readable" do
        expect(buffer).to eq("name=john&")
        expect(body.read).to eq("name=john&role=admin")
      end
    end

    context "when body is a rewindable IO with binary encoding" do
      let(:buffer) { described_class.read_stream(StringIO.new("name=john".b), limit: 9) }

      it { expect(buffer.encoding).to eq(Encoding::BINARY) }
    end

    context "when body returns short reads" do
      before do
        allow(body).to receive(:read).and_wrap_original do |method, length = nil, *args|
          method.call(length && [length, 5].min, *args)
        end
      end

      let(:buffer) { described_class.read_stream(body, limit: 9, rewind_before_read: true) }
      let(:body) { StringIO.new("name=john") }

      it "returns the full body and keeps it readable" do
        expect(buffer).to eq("name=john")
        expect(body.read).to eq("name=john")
      end
    end

    context "when body was already consumed" do
      before { body.read }

      let(:buffer) { described_class.read_stream(body, limit: 9, rewind_before_read: true) }
      let(:body) { StringIO.new("name=john") }

      it "rewinds before reading and after reading" do
        expect(buffer).to eq("name=john")
        expect(body.read).to eq("name=john")
      end
    end

    context "when rewind fails" do
      before do
        allow(Datadog).to receive(:logger).and_return(logger)
        allow(body).to receive(:rewind).and_raise(IOError, "cannot rewind")
      end

      let(:buffer) { described_class.read_stream(body, limit: 9, rewind_before_read: true) }
      let(:body) { StringIO.new("name=john") }
      let(:logger) { instance_double(Datadog::Core::Logger, debug: nil) }

      it "returns nil and logs the rewind failure" do
        expect(buffer).to be_nil
        expect(logger).to have_received(:debug)
      end
    end

    context "when read fails" do
      before do
        allow(body).to receive(:read).and_wrap_original do |method, length = nil, *args|
          raise IOError, "cannot read" unless body.pos.zero?

          method.call(length && [length, 5].min, *args)
        end
      end

      let(:buffer) { described_class.read_stream(body, limit: 9, rewind_before_read: true) }
      let(:body) { StringIO.new("name=john") }

      it "raises the read failure and keeps the body readable" do
        expect { buffer }.to raise_error(IOError, "cannot read")
        expect(body.read).to eq("name=john")
      end
    end

    context "when rewind after reading fails" do
      before do
        allow(Datadog).to receive(:logger).and_return(logger)

        allow(body).to receive(:rewind).and_wrap_original do |method|
          raise IOError, "cannot rewind" unless body.pos.zero?

          method.call
        end
      end

      let(:buffer) { described_class.read_stream(body, limit: 9, rewind_before_read: true) }
      let(:body) { StringIO.new("name=john") }
      let(:logger) { instance_double(Datadog::Core::Logger, debug: nil) }

      it "returns the body and logs the rewind failure" do
        expect(buffer).to eq("name=john")
        expect(logger).to have_received(:debug)
      end
    end

    context "when body is a forward-only reader" do
      before { allow(body).to receive(:read).and_return("name=john", nil) }

      let(:buffer) { described_class.read_stream(body, limit: 9) }
      let(:body) { double("body") }

      it { expect(buffer).to eq("name=john") }
    end

    context "when body is a forward-only reader and exceeds the limit" do
      before { allow(body).to receive(:read).and_return("name=john!", nil) }

      let(:buffer) { described_class.read_stream(body, limit: 9) }
      let(:body) { double("body") }

      it { expect(buffer).to eq("name=john!") }
    end
  end
end
