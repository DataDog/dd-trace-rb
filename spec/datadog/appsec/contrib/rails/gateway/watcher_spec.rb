# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/rails/gateway/watcher"
require "datadog/appsec/contrib/rails/gateway/request"
require "action_dispatch"
require "libddwaf"

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
            "server.request.body" => {"name" => "john"},
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
            "server.request.body.byte_length" => 9,
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
            "server.request.body" => {"name" => "john"},
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
            "server.request.body.byte_length" => 9,
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
            "server.request.body.byte_length" => 9,
          }, {}, anything
        )
      end
    end
  end

  describe ".watch_response_body_json" do
    before do
      described_class.watch_response_body_json(gateway)
      allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(7)
    end

    let(:container) do
      Datadog::AppSec::Instrumentation::Gateway::DataContainer.new('{"x":1}', context: context)
    end

    it "passes marked JSON at the byte limit to the WAF" do
      gateway.push("rails.response.body.json", container)

      expect(context).to have_received(:run_waf).with(
        {
          "server.response.body" => an_instance_of(Datadog::AppSec::WAF::JSONString).and(eq('{"x":1}')),
          "server.response.body.byte_length" => 7,
        }, {}, anything,
      )
    end

    it "does not parse JSON in Ruby" do
      expect(JSON).not_to receive(:parse)

      gateway.push("rails.response.body.json", container)
    end

    context "when the response exceeds the byte limit" do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(6) }

      it "sends the byte length without wrapping the body" do
        expect(Datadog::AppSec::WAF::JSONString).not_to receive(:new)

        gateway.push("rails.response.body.json", container)

        expect(context).to have_received(:run_waf).with(
          {"server.response.body.byte_length" => 7}, {}, anything,
        )
      end
    end

    context "when the response contains multibyte characters" do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(3) }

      let(:container) do
        Datadog::AppSec::Instrumentation::Gateway::DataContainer.new('"é"', context: context)
      end

      it "compares bytes rather than characters" do
        expect(Datadog::AppSec::WAF::JSONString).not_to receive(:new)

        gateway.push("rails.response.body.json", container)

        expect(context).to have_received(:run_waf).with(
          {"server.response.body.byte_length" => 4}, {}, anything,
        )
      end
    end

    context "when body collection is disabled" do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(0) }

      it "sends only the byte length" do
        gateway.push("rails.response.body.json", container)

        expect(context).to have_received(:run_waf).with(
          {"server.response.body.byte_length" => 7}, {}, anything,
        )
      end
    end

    context "when the limit is negative" do
      before { allow(Datadog.configuration.appsec).to receive(:body_parsing_size_limit).and_return(-1) }

      it "sends only the byte length" do
        gateway.push("rails.response.body.json", container)

        expect(context).to have_received(:run_waf).with(
          {"server.response.body.byte_length" => 7}, {}, anything,
        )
      end
    end

    context "when native JSON conversion fails" do
      before do
        allow(context).to receive(:run_waf).and_raise(Datadog::AppSec::WAF::ConversionError, "Could not convert JSON string")
      end

      it "continues the gateway stack" do
        expect(
          gateway.push("rails.response.body.json", container) { :response },
        ).to eq([:response, nil])
      end
    end

    context "when the downstream callback raises a conversion error" do
      before do
        allow(callback).to receive(:call)
          .and_raise(Datadog::AppSec::WAF::ConversionError, "downstream failure")
      end

      let(:callback) { instance_double(Proc) }

      it "propagates the error without retrying the callback" do
        expect { gateway.push("rails.response.body.json", container) { callback.call } }
          .to raise_error(Datadog::AppSec::WAF::ConversionError, "downstream failure")

        expect(callback).to have_received(:call)
      end
    end

    context "when WAF raises an unrelated error" do
      before { allow(context).to receive(:run_waf).and_raise(ArgumentError, "unexpected error") }

      it "propagates the error" do
        expect { gateway.push("rails.response.body.json", container) }
          .to raise_error(ArgumentError, "unexpected error")
      end
    end
  end
end
