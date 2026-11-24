# frozen_string_literal: true

require "datadog/tracing/component"
require "datadog/tracing/diagnostics/environment_logger"
require "datadog/tracing/transport/native"

RSpec.describe "Native transport configuration" do
  before do
    skip_if_libdatadog_not_supported
  end

  describe "Datadog::Tracing::Component.build_writer" do
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        s.tracing.native_transport = native_transport_enabled
      end
    end
    let(:agent_settings) do
      double("agent_settings", url: "http://127.0.0.1:8126", timeout_seconds: 30)
    end
    let(:logger) { Logger.new(File::NULL) }

    before { allow(Datadog).to receive(:logger).and_return(logger) }

    # Some examples build a writer backed by the native transport. Dispose it
    # afterwards so its exporter is freed during the run rather than surviving
    # to interpreter exit, where freeing it after a fork can deadlock.
    let(:built_writers) { [] }

    def build_writer
      Datadog::Tracing::Component.send(:build_writer, settings, agent_settings).tap do |writer|
        built_writers << writer
      end
    end

    after do
      built_writers.each do |writer|
        transport = writer.instance_variable_get(:@transport)
        next unless transport.is_a?(Datadog::Tracing::Transport::Native::Transport)

        NativeTransportForkIsolation.dispose(transport)
      end
    end

    context "when native_transport is false" do
      let(:native_transport_enabled) { false }

      it "builds a writer with the default HTTP transport" do
        writer = build_writer
        expect(writer).to be_a(Datadog::Tracing::Writer)
        # The transport should NOT be our native one
        transport = writer.instance_variable_get(:@transport)
        expect(transport).not_to be_a(Datadog::Tracing::Transport::Native::Transport)
      end
    end

    context "on CRuby 3.4.6 without an explicit setting" do
      let(:settings) { Datadog::Core::Configuration::Settings.new }

      before do
        stub_const("RUBY_ENGINE", "ruby")
        stub_const("Datadog::RubyVersion::CURRENT_RUBY_VERSION", Gem::Version.new("3.4.6"))
      end

      around do |example|
        ClimateControl.modify("DD_EXPERIMENTAL_NATIVE_TRANSPORT_ENABLED" => nil) { example.run }
      end

      it "builds a writer with the native transport by default" do
        expect(build_writer.transport).to be_a(Datadog::Tracing::Transport::Native::Transport)
      end
    end

    context "when native_transport is true" do
      let(:native_transport_enabled) { true }

      context "with resolved Agent settings" do
        let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

        [false, true].each do |uds|
          context "over #{uds ? "a Unix socket" : "HTTP"}" do
            before do
              settings.agent.uds_path = "/tmp/native-timeout.socket" if uds
              settings.agent.timeout_seconds = 7
            end

            it "forwards the configured timeout in milliseconds" do
              expect(Datadog::Tracing::Transport::Native::TraceExporter).to receive(:_native_new)
                .with(hash_including(timeout_milliseconds: 7000)).and_call_original

              build_writer
            end
          end
        end

        context "with an environment timeout" do
          around do |example|
            ClimateControl.modify("DD_TRACE_AGENT_TIMEOUT_SECONDS" => "11") { example.run }
          end

          it "forwards the resolved timeout in milliseconds" do
            expect(Datadog::Tracing::Transport::Native::TraceExporter).to receive(:_native_new)
              .with(hash_including(timeout_milliseconds: 11000)).and_call_original

            build_writer
          end
        end
      end

      it "builds a writer with the native transport" do
        writer = build_writer
        expect(writer).to be_a(Datadog::Tracing::Writer)
        transport = writer.instance_variable_get(:@transport)
        expect(transport).to be_a(Datadog::Tracing::Transport::Native::Transport)
      end

      ["http://127.0.0.1:9/", "http://[::1]:9/", "unix:///tmp/native-diagnostics.socket"].each do |url|
        context "with Agent URL #{url}" do
          let(:agent_settings) { double("agent_settings", url: url, timeout_seconds: 30) }

          it "reports the native destination in startup diagnostics" do
            tracer = instance_double(Datadog::Tracing::Tracer, writer: build_writer)
            allow(Datadog::Tracing).to receive(:tracer).and_return(tracer)

            expect(Datadog::Tracing::Diagnostics::EnvironmentCollector.agent_url).to eq(url)
          end
        end
      end
    end

    context "on CRuby 4.0.0 without an explicit setting" do
      let(:settings) { Datadog::Core::Configuration::Settings.new }

      around do |example|
        ClimateControl.modify("DD_EXPERIMENTAL_NATIVE_TRANSPORT_ENABLED" => nil) { example.run }
      end

      before do
        stub_const("RUBY_ENGINE", "ruby")
        stub_const("Datadog::RubyVersion::CURRENT_RUBY_VERSION", Gem::Version.new("4.0.0"))
      end

      it "selects the native transport by default" do
        expect(build_writer.transport).to be_a(Datadog::Tracing::Transport::Native::Transport)
      end

      context "when the native extension is unavailable" do
        before { allow(Datadog::Tracing::Transport::Native).to receive(:supported?).and_return(false) }

        it "falls back to the Ruby HTTP transport" do
          expect(logger).to receive(:warn).with(/not available/)
          expect(build_writer.transport).to be_a(Datadog::Tracing::Transport::Traces::Transport)
        end
      end
    end

    context "when native_transport is true but native extension is unavailable" do
      let(:native_transport_enabled) { true }

      before do
        allow(Datadog::Tracing::Transport::Native).to receive(:supported?).and_return(false)
        stub_const("Datadog::Tracing::Transport::Native::UNSUPPORTED_REASON", "test: not available")
      end

      it "falls back to the default HTTP transport with a warning" do
        expect(logger).to receive(:warn).with(/not available/)
        writer = build_writer
        transport = writer.instance_variable_get(:@transport)
        expect(transport).not_to be_a(Datadog::Tracing::Transport::Native::Transport)
      end
    end
  end

  describe "settings" do
    it "has native_transport defaulting to true" do
      settings = Datadog::Core::Configuration::Settings.new
      expect(settings.tracing.native_transport).to be true
    end

    it "can be set to false" do
      settings = Datadog::Core::Configuration::Settings.new
      settings.tracing.native_transport = false
      expect(settings.tracing.native_transport).to be false
    end
  end
end
