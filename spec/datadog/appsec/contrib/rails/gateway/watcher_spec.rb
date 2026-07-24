# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/rails/gateway/watcher"
require "datadog/appsec/contrib/rails/gateway/request"
require "action_dispatch"

RSpec.describe Datadog::AppSec::Contrib::Rails::Gateway::Watcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  let(:context) do
    instance_double(
      Datadog::AppSec::Context,
      run_waf: waf_result,
      events: [],
      trace: instance_double(Datadog::Tracing::TraceOperation),
      span: instance_double(Datadog::Tracing::SpanOperation)
    )
  end

  let(:waf_result) do
    instance_double(
      Datadog::AppSec::SecurityEngine::Result::Ok,
      match?: false,
      attributes: [],
      actions: {},
      keep?: false
    )
  end

  describe ".watch_request_action" do
    before do
      described_class.watch_request_action(gateway)
      allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(100)
      allow(gateway_request).to receive(:body_bytesize).with(100).and_return(9)
    end

    let(:gateway_request) do
      instance_double(
        Datadog::AppSec::Contrib::Rails::Gateway::Request,
        env: {Datadog::AppSec::Ext::CONTEXT_KEY => context},
        route_params: {id: "1"},
        parsed_body: {"name" => "john"},
        request: instance_double(ActionDispatch::Request)
      )
    end

    context "when the body is collectable and within the limit" do
      it "runs WAF with path params, body and its byte length" do
        gateway.push("rails.request.action", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {
            "server.request.path_params" => {id: "1"},
            "server.request.body.byte_length" => 9,
            "server.request.body" => {"name" => "john"}
          }, {}, anything
        )
      end
    end

    context "when the body exceeds the parsing size limit" do
      before do
        allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(4)
        allow(gateway_request).to receive(:body_bytesize).with(4).and_return(9)
      end

      it "runs WAF with path params and byte length but without the body" do
        gateway.push("rails.request.action", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {
            "server.request.path_params" => {id: "1"},
            "server.request.body.byte_length" => 9
          }, {}, anything
        )
      end

      it "does not parse the body" do
        gateway.push("rails.request.action", gateway_request)

        expect(gateway_request).not_to have_received(:parsed_body)
      end
    end

    context "when the body was parsed but its size is zero" do
      before { allow(gateway_request).to receive(:body_bytesize).with(100).and_return(0) }

      it "runs WAF with path params and the parsed body but without a byte length" do
        gateway.push("rails.request.action", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {
            "server.request.path_params" => {id: "1"},
            "server.request.body" => {"name" => "john"}
          }, {}, anything
        )
      end
    end

    context "when the body size cannot be measured within the limit" do
      before { allow(gateway_request).to receive(:body_bytesize).with(100).and_return(nil) }

      it "runs WAF with only the path params" do
        gateway.push("rails.request.action", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {"server.request.path_params" => {id: "1"}}, {}, anything
        )
      end

      it "does not parse the body" do
        gateway.push("rails.request.action", gateway_request)

        expect(gateway_request).not_to have_received(:parsed_body)
      end
    end

    context "when body collection is disabled" do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(0) }

      it "runs WAF with only the path params" do
        gateway.push("rails.request.action", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {"server.request.path_params" => {id: "1"}}, {}, anything
        )
      end

      it "does not measure the body" do
        gateway.push("rails.request.action", gateway_request)

        expect(gateway_request).not_to have_received(:body_bytesize)
      end
    end

    context "when the body is collectable but the parsed body is empty" do
      before { allow(gateway_request).to receive(:parsed_body).and_return({}) }

      it "runs WAF with path params and byte length but without the body" do
        gateway.push("rails.request.action", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {
            "server.request.path_params" => {id: "1"},
            "server.request.body.byte_length" => 9
          }, {}, anything
        )
      end
    end

    context "when the body is collectable but the parsed body is nil" do
      before { allow(gateway_request).to receive(:parsed_body).and_return(nil) }

      it "runs WAF with path params and byte length but without the body" do
        gateway.push("rails.request.action", gateway_request)

        expect(context).to have_received(:run_waf).with(
          {
            "server.request.path_params" => {id: "1"},
            "server.request.body.byte_length" => 9
          }, {}, anything
        )
      end
    end
  end
end
