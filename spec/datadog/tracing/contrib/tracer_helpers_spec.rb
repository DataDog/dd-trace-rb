# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"

RSpec.describe Contrib::TracerHelpers do
  describe "#trace_transport_hostname" do
    subject(:hostname) { helper.trace_transport_hostname }

    let(:helper) { Object.new.extend(described_class) }
    let(:test_tracer) { double("tracer", writer: double("writer", transport: transport)) }

    before { allow(helper).to receive(:tracer).and_return(test_tracer) }

    context "with a native transport without a Ruby HTTP client" do
      let(:transport) { double("native transport", url: url) }
      let(:url) { "http://test-agent:9126/" }

      it { is_expected.to eq("test-agent") }

      context "with IPv6" do
        let(:url) { "http://[::1]:9126/" }

        it { is_expected.to eq("::1") }
      end

      context "with a Unix socket" do
        let(:url) { "unix:///tmp/apm.socket" }

        it { is_expected.to be_nil }
      end
    end

    context "with a Ruby HTTP transport" do
      let(:transport) { double("HTTP transport", client: double(instance: double(adapter: adapter))) }
      let(:adapter) { double("HTTP adapter", hostname: "test-agent") }

      it { is_expected.to eq("test-agent") }

      context "with a Unix socket adapter" do
        let(:adapter) { double("Unix socket adapter") }

        it { is_expected.to be_nil }
      end
    end

    context "with a custom transport" do
      let(:transport) { double("custom transport") }

      it { is_expected.to be_nil }
    end

    context "with a tracer without a writer" do
      let(:test_tracer) { double("custom tracer") }

      it { is_expected.to be_nil }
    end
  end
end
