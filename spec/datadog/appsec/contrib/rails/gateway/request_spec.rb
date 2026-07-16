# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/rails/gateway/request"
require "action_dispatch"

RSpec.describe Datadog::AppSec::Contrib::Rails::Gateway::Request do
  subject(:request) { described_class.new(ActionDispatch::Request.new(env)) }

  let(:env) do
    Rack::MockRequest.env_for(
      "http://example.com:8080/",
      {
        :method => "POST",
        :input => "name=john",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      },
    )
  end

  describe "#route_params" do
    context "when the router has populated path parameters" do
      before do
        env["action_dispatch.request.path_parameters"] = {controller: "users", action: "show", id: "42"}
      end

      it "returns the path parameters without :controller and :action" do
        expect(request.route_params).to eq(id: "42")
      end
    end

    context "when the router was bypassed and path parameters are nil" do
      before { env.delete("action_dispatch.request.path_parameters") }

      it "returns an empty hash instead of raising" do
        expect(request.route_params).to eq({})
      end
    end
  end

  describe "#parsed_body" do
    context "when the router has populated path parameters" do
      before do
        env["action_dispatch.request.request_parameters"] = {"name" => "john"}
        env["action_dispatch.request.path_parameters"] = {id: "42"}
      end

      it "returns the request body parameters" do
        expect(request.parsed_body).to eq("name" => "john")
      end
    end

    context "when the router was bypassed and path parameters are nil" do
      before do
        env["action_dispatch.request.request_parameters"] = {"name" => "john"}
        env.delete("action_dispatch.request.path_parameters")
      end

      it "returns the request parameters" do
        expect(request.parsed_body).to eq("name" => "john")
      end
    end

    context "when body parsing fails" do
      before do
        allow(request.request).to receive(:parameters)
          .and_raise(EOFError, "bad multipart")
      end

      it "returns nil and reports telemetry" do
        expect(Datadog::AppSec.telemetry).to receive(:report)
          .with(instance_of(EOFError), description: "AppSec: Failed to parse request body")

        expect(request.parsed_body).to be_nil
      end
    end
  end

  describe "#body_bytesize" do
    context "when raw posted data is present" do
      before { env["RAW_POST_DATA"] = '{"name":"john"}' }

      it { expect(request.body_bytesize(100)).to eq(15) }
    end

    context "when raw form vars are present" do
      before { env["rack.request.form_vars"] = "name=john" }

      it { expect(request.body_bytesize(100)).to eq(9) }
    end

    context "when the body stream reports its size" do
      it { expect(request.body_bytesize(100)).to eq(9) }
    end

    context "when there is no request body" do
      before { env["rack.input"] = nil }

      it { expect(request.body_bytesize(100)).to eq(0) }
    end

    context "when the size is unknown but Content-Length is set" do
      before do
        env["CONTENT_LENGTH"] = "42"
        env["rack.input"] = sizeless_io
      end

      let(:sizeless_io) do
        StringIO.new("name=john").tap do |io|
          allow(io).to receive(:respond_to?).and_call_original
          allow(io).to receive(:respond_to?).with(:size).and_return(false)
        end
      end

      it "returns the Content-Length without reading the body" do
        expect(request.body_bytesize(100)).to eq(42)
        expect(env["rack.input"]).to be(sizeless_io)
      end
    end

    context "when the body was already consumed and has no raw cache" do
      before do
        env.delete("CONTENT_LENGTH")
        env["rack.input"] = consumed_io
      end

      let(:consumed_io) do
        StringIO.new("name=john").tap do |io|
          io.read
          allow(io).to receive(:respond_to?).and_call_original
          allow(io).to receive(:respond_to?).with(:size).and_return(false)
        end
      end

      context "when Rack 3 or later is used" do
        before { skip "Rack 3 or later behavior" if Gem::Version.new(::Rack.release) < Gem::Version.new("3") }

        it { expect(request.body_bytesize(100)).to eq(0) }
      end

      context "when Rack 2 or earlier is used" do
        before { skip "Rack 2 or earlier behavior" if Gem::Version.new(::Rack.release) >= Gem::Version.new("3") }

        it "rewinds the input and measures the full body" do
          expect(request.body_bytesize(100)).to eq(9)
          expect(env["rack.input"]).to be(consumed_io)
          expect(env["rack.input"].read).to eq("name=john")
        end
      end
    end

    context "when the size is unknown and there is no Content-Length" do
      before do
        env.delete("CONTENT_LENGTH")
        env["rack.input"] = body_io
      end

      let(:body_io) do
        StringIO.new("name=john").tap do |io|
          allow(io).to receive(:respond_to?).and_call_original
          allow(io).to receive(:respond_to?).with(:size).and_return(false)
        end
      end

      context "when peeking the input fails" do
        before do
          allow(Datadog).to receive(:logger).and_return(logger)
          allow(Datadog::AppSec::Contrib::Rack::InputPeeker).to receive(:peek_bytesize).and_raise(IOError, "cannot peek")
        end

        let(:logger) { instance_double(Datadog::Core::Logger, debug: nil) }

        it "returns nil and logs the failure" do
          expect(request.body_bytesize(100)).to be_nil
          expect(logger).to have_received(:debug)
        end
      end

      context "when Rack 3 or later is used" do
        before { skip "Rack 3 or later behavior" if Gem::Version.new(::Rack.release) < Gem::Version.new("3") }

        context "when the body fits within the limit" do
          it "buffers the body and returns its byte length" do
            expect(request.body_bytesize(100)).to eq(9)
            expect(env["rack.input"]).to be_a(StringIO)
            expect(env["rack.input"].read).to eq("name=john")
          end
        end

        context "when the body exceeds the limit" do
          it "wraps the body in a forward-only input and returns nil" do
            expect(request.body_bytesize(4)).to be_nil
            expect(env["rack.input"]).to be_a(Datadog::AppSec::Contrib::Rack::BufferedInput)
            expect(env["rack.input"].read).to eq("name=john")
          end
        end
      end

      context "when Rack 2 or earlier is used" do
        before { skip "Rack 2 or earlier behavior" if Gem::Version.new(::Rack.release) >= Gem::Version.new("3") }

        context "when the body fits within the limit" do
          it "rewinds the input in place and returns its byte length" do
            expect(request.body_bytesize(100)).to eq(9)
            expect(env["rack.input"]).to be(body_io)
            expect(env["rack.input"].read).to eq("name=john")
          end
        end

        context "when the body exceeds the limit" do
          it "rewinds the input in place and returns nil" do
            expect(request.body_bytesize(4)).to be_nil
            expect(env["rack.input"]).to be(body_io)
            expect(env["rack.input"].read).to eq("name=john")
          end
        end
      end
    end
  end
end
