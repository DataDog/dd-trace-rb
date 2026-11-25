require "spec_helper"

require "datadog/core/transport/http"

RSpec.describe Datadog::Core::Transport::HTTP do
  describe ".build" do
    subject(:builder) do
      described_class.build(agent_settings: agent_settings, logger: logger, **options) { |transport| transport }
    end

    let(:logger) { instance_double(Datadog::Core::Logger, warn: nil) }
    let(:options) { {} }
    let(:adapter_name) { Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER }
    let(:agent_settings) do
      Datadog::Core::Configuration::AgentSettings.new(
        adapter: adapter_name, hostname: "agent", port: 8126, ssl: false, timeout_seconds: 5,
      )
    end
    let(:native_http) { true }
    let(:native_adapter) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Native) }

    before do
      allow(Datadog.configuration.agent).to receive(:native_http).and_return(native_http)
      allow(Datadog::Core::Transport::HTTP::Adapters::Native).to receive_messages(unsupported_reason: nil, build: native_adapter)
      described_class.send(:remove_const, :NATIVE_UNSUPPORTED_WARNING)
      described_class.const_set(:NATIVE_UNSUPPORTED_WARNING, Datadog::Core::Utils::OnlyOnce.new)
    end

    context "with the native HTTP client disabled" do
      let(:native_http) { false }

      it "uses the default adapter" do
        expect(builder.default_adapter).to be_a(Datadog::Core::Transport::HTTP::Adapters::Net)
        expect(Datadog::Core::Transport::HTTP::Adapters::Native).not_to have_received(:build)
      end
    end

    context "with the native HTTP client enabled" do
      it "uses the native adapter" do
        expect(builder.default_adapter).to be(native_adapter)
        expect(Datadog::Core::Transport::HTTP::Adapters::Native).to have_received(:build).with(agent_settings)
      end

      context "with a Unix socket" do
        let(:adapter_name) { Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER }
        let(:agent_settings) do
          Datadog::Core::Configuration::AgentSettings.new(
            adapter: adapter_name, uds_path: "/tmp/agent.sock", timeout_seconds: 5,
          )
        end

        it { expect(builder.default_adapter).to be(native_adapter) }
      end

      context "when the caller opts out" do
        let(:options) { {native: false} }

        it "uses the default adapter" do
          expect(builder.default_adapter).to be_a(Datadog::Core::Transport::HTTP::Adapters::Net)
          expect(Datadog::Core::Transport::HTTP::Adapters::Native).not_to have_received(:build)
        end
      end

      context "when the native HTTP client is not available" do
        before do
          allow(Datadog::Core::Transport::HTTP::Adapters::Native).to receive(:unsupported_reason).and_return("no extension")
        end

        it "falls back to the default adapter, and warns only once" do
          2.times { described_class.build(agent_settings: agent_settings, logger: logger) { |transport| transport } }

          expect(builder.default_adapter).to be_a(Datadog::Core::Transport::HTTP::Adapters::Net)
          expect(logger).to have_received(:warn).with(/not available: no extension.*Falling back/).once
        end
      end

      context "when the native adapter cannot be created" do
        before do
          allow(Datadog::Core::Transport::HTTP::Adapters::Native).to receive(:build).and_raise("boom")
        end

        it "falls back to the default adapter, and warns" do
          expect(builder.default_adapter).to be_a(Datadog::Core::Transport::HTTP::Adapters::Net)
          expect(logger).to have_received(:warn).with(/could not be created.*RuntimeError: boom/)
        end
      end
    end
  end

  describe ".default_headers" do
    subject(:default_headers) { described_class.default_headers }

    it do
      is_expected.to include(
        Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_TOP_LEVEL => "1",
        Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG => Datadog::Core::Environment::Ext::LANG,
        Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG_VERSION => Datadog::Core::Environment::Ext::LANG_VERSION,
        Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER =>
          Datadog::Core::Environment::Ext::LANG_INTERPRETER,
        "Datadog-Meta-Lang-Interpreter-Vendor" => RUBY_ENGINE,
        Datadog::Core::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION =>
          Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION,
      )
    end

    context "when Container.to_headers returns headers" do
      let(:container_headers) do
        {
          "Datadog-Container-ID" => "abc123",
          "Datadog-Entity-ID" => "ci-abc123",
          "Datadog-External-Env" => "provided-by-container-runner",
        }
      end

      before do
        allow(Datadog::Core::Environment::Container).to receive(:to_headers).and_return(container_headers)
      end

      it "merges container headers into default headers" do
        expect(default_headers).to include(container_headers)
      end
    end

    context "when Container.to_headers returns empty hash" do
      before do
        allow(Datadog::Core::Environment::Container).to receive(:to_headers).and_return({})
      end

      it "does not include any container headers" do
        expect(default_headers).to_not include("Datadog-Container-ID")
        expect(default_headers).to_not include("Datadog-Entity-ID")
        expect(default_headers).to_not include("Datadog-External-Env")
      end
    end

    context "when Datadog.configuration.apm.tracing.enabled" do
      before { expect(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(apm_tracing_enabled) }

      context "is false" do
        let(:apm_tracing_enabled) { false }

        it { is_expected.to include(Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS => "yes") }
      end

      context "is true" do
        let(:apm_tracing_enabled) { true }

        it { is_expected.to_not include(Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS) }
      end
    end
  end
end
