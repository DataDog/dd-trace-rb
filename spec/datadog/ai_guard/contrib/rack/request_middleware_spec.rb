# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"

require "datadog"
require "datadog/ai_guard"
require "rack"

RSpec.describe Datadog::AIGuard::Contrib::Rack::RequestMiddleware do
  subject(:middleware) { described_class.new(app) }

  let(:app) { ->(_env) { [200, {}, ["ok"]] } }
  let(:env) do
    {
      "REMOTE_ADDR" => "203.0.113.5",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.42",
      "PATH_INFO" => "/",
      "REQUEST_METHOD" => "GET",
    }
  end

  before do
    Datadog.configure do |c|
      c.ai_guard.enabled = true
    end
  end

  after do
    Datadog.configuration.reset!
  end

  context "when AI Guard ran during the request" do
    let(:app) do
      lambda do |_env|
        Datadog::Tracing.active_trace&.set_tag(Datadog::AIGuard::Ext::SERVICE_ENTRY_EXECUTED_TAG, "1")
        [200, {}, ["ok"]]
      end
    end

    it "tags http.client_ip and network.client.ip on the request span" do
      Datadog::Tracing.trace("rack.request") do |span|
        middleware.call(env)

        expect(span.get_tag("http.client_ip")).to eq("198.51.100.42")
        expect(span.get_tag("network.client.ip")).to eq("203.0.113.5")
      end
    end

    it "passes the request through" do
      response = nil
      Datadog::Tracing.trace("rack.request") do
        response = middleware.call(env)
      end

      expect(response).to eq([200, {}, ["ok"]])
    end

    it "removes the executed flag from the trace so it is not exported" do
      Datadog::Tracing.trace("rack.request") do |_span, trace|
        middleware.call(env)

        expect(trace.get_tag(Datadog::AIGuard::Ext::SERVICE_ENTRY_EXECUTED_TAG)).to be_nil
      end
    end

    it "still tags on the way out when the inner app raises" do
      raising_app = lambda do |_env|
        Datadog::Tracing.active_trace&.set_tag(Datadog::AIGuard::Ext::SERVICE_ENTRY_EXECUTED_TAG, "1")
        raise "boom"
      end
      mw = described_class.new(raising_app)

      Datadog::Tracing.trace("rack.request") do |span|
        expect { mw.call(env) }.to raise_error(RuntimeError, "boom")

        expect(span.get_tag("http.client_ip")).to eq("198.51.100.42")
        expect(span.get_tag("network.client.ip")).to eq("203.0.113.5")
      end
    end

    context "when REMOTE_ADDR is missing" do
      let(:env) { super().tap { |e| e.delete("REMOTE_ADDR") } }

      it "does not set network.client.ip" do
        Datadog::Tracing.trace("rack.request") do |span|
          middleware.call(env)

          expect(span.get_tag("network.client.ip")).to be_nil
        end
      end
    end

    context "when tagging raises" do
      before do
        allow(Datadog::Tracing::ClientIp).to receive(:set_client_ip_tag!).and_raise(StandardError, "boom")
      end

      it "reports to telemetry instead of raising" do
        telemetry = instance_double(Datadog::Core::Telemetry::Component)
        allow(Datadog::AIGuard).to receive(:telemetry).and_return(telemetry)
        expect(telemetry).to receive(:report).with(an_instance_of(StandardError), description: a_string_including("AI Guard"))

        Datadog::Tracing.trace("rack.request") do
          expect { middleware.call(env) }.not_to raise_error
        end
      end
    end
  end

  context "when AI Guard did not run during the request" do
    it "does not tag the request span" do
      Datadog::Tracing.trace("rack.request") do |span|
        middleware.call(env)

        expect(span.get_tag("http.client_ip")).to be_nil
        expect(span.get_tag("network.client.ip")).to be_nil
      end
    end

    it "still passes the request through" do
      Datadog::Tracing.trace("rack.request") do
        expect(middleware.call(env)).to eq([200, {}, ["ok"]])
      end
    end
  end

  context "when there is no active trace" do
    let(:app) do
      lambda do |_env|
        Datadog::Tracing.trace(Datadog::AIGuard::Ext::SPAN_NAME) do |_span, trace|
          trace.set_tag(Datadog::AIGuard::Ext::SERVICE_ENTRY_EXECUTED_TAG, "1")
        end
        [200, {}, ["ok"]]
      end
    end

    it "does not raise" do
      expect { middleware.call(env) }.not_to raise_error
    end
  end
end
