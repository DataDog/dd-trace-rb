# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/native_output_helpers"
require "datadog/appsec/contrib/rack/gateway/watcher"
require "datadog/appsec/contrib/rack/gateway/request"
require "rack"
require "datadog/appsec/contrib/rack/gateway/response"

RSpec.describe Datadog::AppSec::Contrib::Rack::Gateway::Watcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  let(:context) do
    instance_double(
      Datadog::AppSec::Context,
      run_waf: waf_result,
      events: [],
      trace: instance_double(Datadog::Tracing::TraceOperation),
      span: instance_double(Datadog::Tracing::SpanOperation),
    )
  end

  let(:waf_result) do
    instance_double(
      Datadog::AppSec::SecurityEngine::Result::Ok,
      match?: false,
      attributes: [],
      actions: {},
      keep?: false,
    )
  end

  describe ".watch_request_body" do
    before { described_class.watch_request_body(gateway) }

    let(:gateway_request) do
      Datadog::AppSec::Contrib::Rack::Gateway::Request.new(
        Rack::MockRequest.env_for(
          "http://example.com/",
          {
            :method => "POST",
            :input => "name=john",
            "CONTENT_TYPE" => "application/x-www-form-urlencoded",
            Datadog::AppSec::Ext::CONTEXT_KEY => context,
          },
        ),
      )
    end

    context "when the body is parsed and within the limit" do
      it "runs WAF with the body and its byte length" do
        gateway.push("rack.request.body", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {"server.request.body" => {"name" => "john"}, "server.request.body.byte_length" => 9}, anything,
        )
      end
    end

    context "when the body does not respond to size" do
      before do
        allow(gateway_request.request).to receive(:body).and_return(Object.new)
        allow(gateway_request.request).to receive(:content_length).and_return(42)
      end

      it "runs WAF with the content length as byte length" do
        gateway.push("rack.request.body", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {"server.request.body" => {"name" => "john"}, "server.request.body.byte_length" => 42}, anything,
        )
      end
    end

    context "when the body size is unknown" do
      before do
        gateway_request.env.delete("CONTENT_LENGTH")
        gateway_request.env["rack.input"] = unsized_io
      end

      let(:unsized_io) do
        StringIO.new("name=john").tap do |io|
          allow(io).to receive(:respond_to?).and_call_original
          allow(io).to receive(:respond_to?).with(:size).and_return(false)
        end
      end

      context "and the body fits within the limit" do
        it "runs WAF with the body and its measured byte length" do
          gateway.push("rack.request.body", gateway_request)

          expect(context).to have_received(:run_waf).with(
            {"server.request.body" => {"name" => "john"}, "server.request.body.byte_length" => 9}, anything,
          )
        end
      end

      context "when the body was already parsed upstream" do
        before do
          gateway_request.env["rack.request.form_hash"] = {"name" => "john"}
          unsized_io.read
        end

        it "runs WAF with the cached body without byte length" do
          gateway.push("rack.request.body", gateway_request)

          expect(context).to have_received(:run_waf).with(
            {"server.request.body" => {"name" => "john"}}, anything,
          )
        end
      end

      context "and the body exceeds the limit" do
        before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(4) }

        it "does not run WAF" do
          gateway.push("rack.request.body", gateway_request)

          expect(context).not_to have_received(:run_waf)
        end

        it "keeps rack input compatible with form parsing" do
          gateway.push("rack.request.body", gateway_request)

          expect(::Rack::Request.new(gateway_request.env).POST).to eq("name" => "john")
        end
      end

      context "and body collection is disabled" do
        before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(0) }

        it "does not run WAF" do
          gateway.push("rack.request.body", gateway_request)

          expect(context).not_to have_received(:run_waf)
        end
      end
    end

    context "when the body exceeds the parsing size limit" do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(4) }

      it "runs WAF with only the byte length" do
        gateway.push("rack.request.body", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {"server.request.body.byte_length" => 9}, anything,
        )
      end

      it "does not parse the form body" do
        allow(gateway_request).to receive(:form_hash)

        gateway.push("rack.request.body", gateway_request)

        expect(gateway_request).not_to have_received(:form_hash)
      end
    end

    context "when the parsing size limit is zero" do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(0) }

      it "does not run WAF" do
        gateway.push("rack.request.body", gateway_request)

        expect(context).not_to have_received(:run_waf)
      end
    end

    context "when no body was parsed" do
      let(:gateway_request) do
        Datadog::AppSec::Contrib::Rack::Gateway::Request.new(
          Rack::MockRequest.env_for(
            "http://example.com/",
            {:method => "GET", Datadog::AppSec::Ext::CONTEXT_KEY => context},
          ),
        )
      end

      it "does not run WAF" do
        gateway.push("rack.request.body", gateway_request)

        expect(context).not_to have_received(:run_waf)
      end
    end
  end
  describe "native output through gateway phases" do
    before do
      described_class.watch_request(gateway)
      described_class.watch_response(gateway)
      described_class.watch_request_body(gateway)
    end

    let(:request) do
      Datadog::AppSec::Contrib::Rack::Gateway::Request.new(
        Rack::MockRequest.env_for("http://example.com/", {
          :method => "POST", :input => "name=john", "CONTENT_TYPE" => "application/x-www-form-urlencoded",
          "HTTP_USER_AGENT" => "ExampleBrowser", Datadog::AppSec::Ext::CONTEXT_KEY => context,
        }),
      )
    end

    context "request headers" do
      let(:output_address) { "server.request.headers.no_cookies" }
      subject(:consume) { gateway.push("rack.request", request) }
      it_behaves_like "a native AppSec output consumer"
    end

    context "request body" do
      let(:output_address) { "server.request.body" }
      subject(:consume) { gateway.push("rack.request.body", request) }
      it_behaves_like "a native AppSec output consumer"
    end

    context "response headers" do
      let(:output_address) { "server.response.headers.no_cookies" }
      subject(:consume) do
        response = Datadog::AppSec::Contrib::Rack::Gateway::Response.new(
          ["ok"], 200, {"content-type" => "text/plain"}, context: context,
        )
        gateway.push("rack.response", response)
      end
      it_behaves_like "a native AppSec output consumer"
    end
  end

  describe "native processor and action output" do
    include_context "native AppSec output"
    let(:output_address) { "server.request.headers.no_cookies" }
    let(:request) do
      Datadog::AppSec::Contrib::Rack::Gateway::Request.new(
        Rack::MockRequest.env_for("http://example.com/", {
          "HTTP_USER_AGENT" => "ExampleBrowser", Datadog::AppSec::Ext::CONTEXT_KEY => context,
        }),
      )
    end
    subject(:consume) { gateway.push("rack.request", request) { :continued } }

    before do
      described_class.watch_request(gateway)
      allow(Datadog::AppSec).to receive(:active_context).and_return(context)
    end

    context "recommended processors" do
      let(:native_rules) do
        Datadog::AppSec::Processor::RuleLoader.load_rules(telemetry: telemetry, ruleset: :recommended)
      end

      it "records benign fingerprints and schemas without attack tags or counters" do
        expect(consume.first).to eq(:continued)
        context.extract_schema!
        Datadog::AppSec::Event.record(context)

        expect(span.tags.keys.grep(/^_dd\.appsec\.fp\./)).not_to be_empty
        expect(span.tags.keys.grep(/^_dd\.appsec\.s\./)).not_to be_empty
        expect(context.state[:schema_extracted]).to be(true)
        expect(span.tags).not_to include("appsec.event", "appsec.blocked", "_dd.appsec.json")
        expect(context.metrics.waf.matches).to eq(0)
        expect(trace.sampling_priority).to eq(2)
        context.export_request_telemetry
        expect(telemetry).to have_received(:inc).with(
          "appsec", "waf.requests", 1, tags: hash_including(rule_triggered: "false"),
        )
      end
    end

    context "attribute output with retention" do
      let(:output_keep) { true }

      it "retains attributes and AppSec origin without tagging an attack" do
        expect(consume.first).to eq(:continued)
        expect(trace.sampling_priority).to eq(2)
        Datadog::AppSec::Event.record(context)
        expect(span.get_tag("test.trace.attribute")).to eq("captured")
        expect(span.get_tag("_dd.origin")).to eq("appsec")
        expect(span.get_tag("appsec.event")).to be_nil
      end
    end

    context "an action without a native event" do
      let(:output_keep) { true }
      let(:native_rules) do
        super().merge("actions" => [{
          "id" => "test-block", "type" => "block_request",
          "parameters" => {"status_code" => 403, "type" => "auto"},
        }]).tap { |rules| rules["rules_compat"].first["on_match"] = ["test-block"] }
      end

      it "captures and retains before blocking" do
        expect(context.catch_interrupt { consume }).to be(true)
        expect(context.events.size).to eq(1)
        expect(context.events.first.waf_result.events).to be_empty
        expect(context.events.first.waf_result).to be_match
        expect(span.get_tag("appsec.blocked")).to eq("true")
        expect(span.get_tag("appsec.event")).to eq("true")
        expect(trace.sampling_priority).to eq(2)
      end
    end
  end
end
