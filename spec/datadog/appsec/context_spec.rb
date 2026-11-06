# frozen_string_literal: true

require "libddwaf"

require "datadog/appsec/spec_helper"
require "datadog/appsec/processor/rule_loader"

RSpec.describe Datadog::AppSec::Context do
  let(:span) { Datadog::Tracing::SpanOperation.new("root") }
  let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.appsec.enabled = true
    end
  end
  let(:security_engine) do
    Datadog::AppSec::SecurityEngine::Engine.new(appsec_settings: settings.appsec, telemetry: telemetry)
  end
  let(:waf_runner) { security_engine.new_runner }
  let(:context) { described_class.new(trace, span, waf_runner) }

  before do
    allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
    allow(telemetry).to receive(:inc)
  end

  after do
    described_class.deactivate
  end

  describe ".active" do
    context "when no active context is set" do
      it { expect(described_class.active).to be_nil }
    end

    context "when active context is set" do
      before { described_class.activate(context) }

      it "returns the active context" do
        expect(described_class.active).to eq(context)
      end
    end

    context "when deactivated context is still referenced from a copied fiber-local" do
      before do
        described_class.activate(context)
        described_class.deactivate

        Thread.current[Datadog::AppSec::Ext::ACTIVE_CONTEXT_KEY] = context
      end

      it { expect(described_class.active).to be_nil }
    end

    context "when deactivated context is still attached and referenced from a copied fiber-local" do
      before do
        described_class.activate(context)
        context.attach
        described_class.deactivate

        Thread.current[Datadog::AppSec::Ext::ACTIVE_CONTEXT_KEY] = context
      end

      after { context.detach }

      it { expect(described_class.active).to eq(context) }
    end
  end

  describe ".activate" do
    it { expect { described_class.activate(double) }.to raise_error(ArgumentError) }

    context "when no active context is set" do
      it "sets the active context" do
        expect { described_class.activate(context) }.to change { described_class.active }.from(nil).to(context)
      end
    end

    context "when active context is already set" do
      before { described_class.activate(context) }

      subject(:activate_context) { described_class.activate(described_class.new(trace, span, waf_runner)) }

      it "raises an error and does not change the active context" do
        expect { activate_context }.to raise_error(Datadog::AppSec::Context::ActiveContextError)
          .and(not_change { described_class.active })
      end
    end
  end

  describe ".deactivate" do
    context "when no active context is set" do
      it "does not change the active context" do
        expect { described_class.deactivate }.to_not(change { described_class.active })
      end
    end

    context "when active context is set" do
      before do
        described_class.activate(context)
        expect(waf_runner).to receive(:finalize!).and_call_original
      end

      it "unsets the active context" do
        expect { described_class.deactivate }.to change { described_class.active }.from(context).to(nil)
      end
    end

    context "when error happen during deactivation" do
      before do
        allow(telemetry).to receive(:report)
        allow(waf_runner).to receive(:finalize!).and_raise(RuntimeError.new("Ooops"))

        described_class.activate(context)
      end

      it "unsets the active context without raising" do
        expect { described_class.deactivate }.to change { described_class.active }.from(context).to(nil)
      end

      it "reports the error to telemetry" do
        described_class.deactivate

        expect(telemetry).to have_received(:report).with(kind_of(RuntimeError), description: kind_of(String))
      end
    end

    context "when another thread is attached" do
      before do
        allow(waf_runner).to receive(:finalize!).and_call_original

        described_class.activate(context)
        context.attach
      end

      after { context.detach }

      it "does not finalize waf runner" do
        described_class.deactivate

        expect(waf_runner).not_to have_received(:finalize!)
      end
    end
  end

  describe "#attach" do
    context "when context is active" do
      before { described_class.activate(context) }

      after { context.detach }

      it { expect(context.attach).to be(true) }
    end

    context "when context was deactivated without other attached threads" do
      before do
        described_class.activate(context)
        described_class.deactivate
      end

      it { expect(context.attach).to be(false) }
    end
  end

  describe "#detach" do
    context "when it detaches the last thread" do
      before do
        allow(waf_runner).to receive(:finalize!).and_call_original

        described_class.activate(context)
        context.attach
        described_class.deactivate
      end

      it "finalizes waf runner" do
        context.detach

        expect(waf_runner).to have_received(:finalize!)
      end
    end

    context "when waf runner fails to finalize" do
      before do
        allow(telemetry).to receive(:report)
        allow(waf_runner).to receive(:finalize!).and_raise(RuntimeError, "Ooops")

        described_class.activate(context)
        context.attach
        described_class.deactivate
      end

      it { expect { context.detach }.not_to raise_error }
    end
  end

  describe "#shared?" do
    it { expect(context.shared?).to be(false) }

    context "when another thread is attached" do
      before { context.attach }

      after { context.detach }

      it { expect(context.shared?).to be(true) }
    end

    context "when another thread was attached and detached" do
      before do
        context.attach
        context.detach
      end

      it { expect(context.shared?).to be(false) }
    end
  end

  describe "#run_waf" do
    context "when multiple same matching runs were made within a single context" do
      let!(:run_results) do
        persistent_data = {
          "server.request.headers.no_cookies" => {"user-agent" => "Nessus SOAP"},
        }

        Array.new(3) { context.run_waf(persistent_data, {}, 1_000_000) }
      end

      it "returns a single match and rest is ok" do
        expect(run_results).to match_array(
          [
            kind_of(Datadog::AppSec::SecurityEngine::Result::Match),
            kind_of(Datadog::AppSec::SecurityEngine::Result::Ok),
            kind_of(Datadog::AppSec::SecurityEngine::Result::Ok),
          ],
        )
      end
    end

    context "when multiple different matching runs were made within a single context" do
      let!(:run_results) do
        persistent_data_1 = {"server.request.query" => {"q" => "1 OR 1;"}}
        persistent_data_2 = {
          "server.request.headers.no_cookies" => {"user-agent" => "Nessus SOAP"},
        }

        [
          context.run_waf(persistent_data_1, {}, 1_000_000),
          context.run_waf(persistent_data_2, {}, 1_000_000),
        ]
      end

      it "returns a single match and rest is ok" do
        expect(run_results).to match_array(
          [
            kind_of(Datadog::AppSec::SecurityEngine::Result::Match),
            kind_of(Datadog::AppSec::SecurityEngine::Result::Match),
          ],
        )
      end
    end
  end

  describe "#run_rasp" do
    context "when a matching run was made" do
      before { allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry) }

      let(:persistent_data) do
        {"server.request.query" => {"q" => "1' OR 1=1;"}}
      end
      let(:ephemeral_data) do
        {
          "server.db.statement" => "SELECT * FROM users WHERE name = '1' OR 1=1;",
          "server.db.system" => "mysql",
        }
      end

      it "sends telemetry metrics" do
        expect(telemetry).to receive(:inc)
          .with("appsec", anything, kind_of(Integer), anything)
          .at_least(:once)

        context.run_rasp("sqli", persistent_data, ephemeral_data, 1_000_000)
      end
    end

    context "when a run was a failure" do
      before do
        allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
        allow_any_instance_of(Datadog::AppSec::SecurityEngine::Runner).to receive(:run)
          .and_return(run_result)
      end

      let(:run_result) do
        Datadog::AppSec::SecurityEngine::Result::Error.new(duration_ext_ns: 0, input_truncated: false)
      end
      let(:persistent_data) do
        {"server.request.query" => {"q" => "1' OR 1=1;"}}
      end
      let(:ephemeral_data) do
        {
          "server.db.statement" => "SELECT * FROM users WHERE name = '1' OR 1=1;",
          "server.db.system" => "mysql",
        }
      end

      it "does not send RASP telemetry metrics" do
        expect(telemetry).not_to receive(:inc)
          .with("appsec", be_in(["rasp.rule.eval", "rasp.rule.match", "rasp.timeout"]), kind_of(Integer), anything)

        context.run_rasp("sqli", persistent_data, ephemeral_data, 1_000_000)
      end
    end

    context "when context was deactivated while another thread is attached" do
      before do
        described_class.activate(context)
        context.attach
        context.run_rasp("sqli", {}, ephemeral_data, 1_000_000)
        described_class.deactivate
      end

      after { context.detach }

      let(:ephemeral_data) do
        {
          "server.db.statement" => "SELECT 1",
          "server.db.system" => "mysql",
        }
      end

      it "runs waf" do
        expect(context.run_rasp("sqli", {}, ephemeral_data, 1_000_000))
          .to be_a(Datadog::AppSec::SecurityEngine::Result::Ok)
      end
    end
  end

  describe "#extract_schema!" do
    before { allow(Datadog.configuration.appsec).to receive(:waf_timeout).and_return(42) }

    it "runs the waf with extract-schema address and the configured timeout" do
      expect_any_instance_of(Datadog::AppSec::SecurityEngine::Runner).to receive(:run)
        .with({"waf.context.processor" => {"extract-schema" => true}}, {}, 42)
        .and_call_original

      context.extract_schema!
    end

    it "stores a new security event" do
      expect { context.extract_schema! }.to change { context.events.count }.by(1)
    end

    context "when created security event has a schema" do
      before do
        allow_any_instance_of(Datadog::AppSec::SecurityEvent).to receive(:schema?).and_return(true)
      end

      it "sets schema_extracted attribute in state to true" do
        expect { context.extract_schema! }.to change { context.state[:schema_extracted] }.from(nil).to(true)
      end
    end

    context "when created security event has no schema" do
      before do
        allow_any_instance_of(Datadog::AppSec::SecurityEvent).to receive(:schema?).and_return(false)
      end

      it "sets schema_extracted attribute in state to false" do
        expect { context.extract_schema! }.to change { context.state[:schema_extracted] }.from(nil).to(false)
      end
    end
  end

  describe "#export_metrics" do
    context "when span is not present" do
      let(:context) { described_class.new(trace, nil, waf_runner) }

      it "does not export metrics" do
        expect(Datadog::AppSec::Metrics::Exporter).not_to receive(:export_waf_metrics)
        expect(Datadog::AppSec::Metrics::Exporter).not_to receive(:export_rasp_metrics)

        context.export_metrics
      end
    end

    context "when span is present" do
      it "exports the metrics" do
        expect(Datadog::AppSec::Metrics::Exporter).to receive(:export_waf_metrics)
        expect(Datadog::AppSec::Metrics::Exporter).to receive(:export_rasp_metrics)

        context.export_metrics
      end
    end
  end

  describe "#catch" do
    before { allow(Datadog.logger).to receive(:warn) }

    let(:steps) { [] }

    it { expect(context.catch { :value }).to eq(:value) }

    context "when work is interrupted" do
      it "returns nil and skips the rest of the work" do
        result = context.catch do
          steps << :before
          context.interrupt!({"status_code" => "403"})
          steps << :after
        end

        expect(result).to be_nil
        expect(steps).to eq([:before])
      end
    end

    context "when catches are nested" do
      it "ends only the inner work" do
        result = context.catch do
          context.catch do
            context.interrupt!({"status_code" => "403"})
            steps << :inner
          end
          steps << :outer

          :outer_value
        end

        expect(result).to eq(:outer_value)
        expect(steps).to eq([:outer])
      end
    end

    context "when work is interrupted from another thread" do
      it "does not end the work and warns in the other thread" do
        result = context.catch do
          Thread.new do
            context.interrupt!({"status_code" => "403"})
            steps << :thread
          end.join
          steps << :caller

          :value
        end

        expect(result).to eq(:value)
        expect(steps).to eq([:thread, :caller])
        expect(Datadog.logger).to have_received(:warn)
      end
    end

    context "when work raises" do
      before do
        context.catch { raise "Ooops" }
      rescue RuntimeError
        nil
      end

      it { expect(context.interrupted?).to be(false) }

      it "ends the next interrupted work" do
        result = context.catch do
          context.interrupt!({"status_code" => "403"})
          steps << :after
        end

        expect(result).to be_nil
        expect(steps).to be_empty
      end
    end
  end

  describe "#interrupt!" do
    before { allow(Datadog.logger).to receive(:warn) }

    let(:steps) { [] }

    it "stores the decision" do
      expect { context.catch { context.interrupt!({"status_code" => "403"}) } }
        .to change { context.state[:interrupt_params] }.from(nil).to({"status_code" => "403"})
    end

    it "throws the action params to a raw catch" do
      expect(catch(Datadog::AppSec::Ext::INTERRUPT) { context.interrupt!({"status_code" => "403"}) })
        .to eq({"status_code" => "403"})
    end

    context "when a decision was already made" do
      before { context.catch { context.interrupt!({"status_code" => "403"}) } }

      it "keeps the first decision" do
        expect { context.catch { context.interrupt!({"status_code" => "303", "location" => "/"}) } }
          .not_to(change { context.state[:interrupt_params] })
      end

      it "keeps the first decision without a catch" do
        expect { context.interrupt!({"status_code" => "303", "location" => "/"}) }
          .not_to(change { context.state[:interrupt_params] })
      end
    end

    context "when context was marked as interrupted" do
      before { context.mark_as_interrupted! }

      it "keeps the mark" do
        context.catch { context.interrupt!({"status_code" => "401"}) }

        expect(context.state[:interrupt_params]).to eq({})
      end

      it "renders the default block response" do
        context.catch { context.interrupt!({"status_code" => "401"}) }

        expect(Datadog::AppSec::Response.from_interrupt_params(context.state[:interrupt_params], nil).status)
          .to eq(403)
      end
    end

    context "when two threads interrupt at the same time" do
      let(:barrier) { Queue.new }
      let(:threads) do
        [{"status_code" => "403"}, {"status_code" => "303", "location" => "/"}].map do |action_params|
          Thread.new do
            barrier.pop
            context.catch { context.interrupt!(action_params) }
          end
        end
      end

      it "stores exactly one of the decisions" do
        threads.size.times { barrier.push(true) }
        threads.each(&:join)

        expect(context.state[:interrupt_params]).to eq({"status_code" => "403"})
          .or(eq({"status_code" => "303", "location" => "/"}))
      end
    end

    context "when there is no catch" do
      it "stores the decision and continues the work" do
        context.interrupt!({"status_code" => "403"})
        steps << :after

        expect(context.state[:interrupt_params]).to eq({"status_code" => "403"})
        expect(steps).to eq([:after])
      end

      it "warns" do
        context.interrupt!({"status_code" => "403"})

        expect(Datadog.logger).to have_received(:warn)
      end
    end

    context "when catch has ended" do
      before { context.catch { :done } }

      it "stores the decision and warns" do
        expect { context.interrupt!({"status_code" => "403"}) }.not_to raise_error

        expect(context.state[:interrupt_params]).to eq({"status_code" => "403"})
        expect(Datadog.logger).to have_received(:warn)
      end
    end
  end

  describe "#interrupted?" do
    it { expect(context.interrupted?).to be(false) }

    context "when context was interrupted" do
      before { context.catch { context.interrupt!({"status_code" => "403"}) } }

      it { expect(context.interrupted?).to be(true) }
    end
  end

  describe "#mark_as_interrupted!" do
    it "marks context as interrupted" do
      expect { context.mark_as_interrupted! }.to change(context, :interrupted?).from(false).to(true)
    end

    context "when a decision was already made" do
      before { context.catch { context.interrupt!({"status_code" => "403"}) } }

      it "keeps the decision" do
        expect { context.mark_as_interrupted! }.not_to(change { context.state[:interrupt_params] })
      end
    end
  end

  describe "#export_request_telemetry" do
    it "calls telemetry exporter" do
      expect(Datadog::AppSec::Metrics::TelemetryExporter).to receive(:export_waf_request_metrics).with(anything, context)
      expect(Datadog::AppSec::Metrics::TelemetryExporter).to receive(:export_api_security_metrics)

      context.export_request_telemetry
    end

    context "when trace is not present" do
      let(:context) { described_class.new(nil, span, waf_runner) }

      it "does not call telemetry exporter" do
        expect(Datadog::AppSec::Metrics::TelemetryExporter).not_to receive(:export_waf_request_metrics)
        expect(Datadog::AppSec::Metrics::TelemetryExporter).not_to receive(:export_api_security_metrics)

        context.export_request_telemetry
      end
    end
  end
end
