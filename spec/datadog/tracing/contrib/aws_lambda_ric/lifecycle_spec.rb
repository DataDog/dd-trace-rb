# frozen_string_literal: true

require "stringio"

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/aws_lambda_ric/lifecycle"

RSpec.describe Datadog::Tracing::Contrib::AwsLambdaRic::Lifecycle do
  let(:http) do
    instance_double(
      Net::HTTP,
      :started? => true,
      :finish => nil,
      "open_timeout=" => nil,
      "read_timeout=" => nil,
    )
  end
  let(:response) { instance_double(Net::HTTPResponse) }
  let(:requests) { [] }
  let(:response_headers) do
    {
      "x-datadog-trace-id" => "123",
      "x-datadog-sampling-priority" => "1",
    }
  end

  before do
    described_class.send(:reset!)
    described_class.instance_variable_set(:@extension_running, true)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) do |request|
      requests << request
      response
    end
    allow(response).to receive(:each_header).and_yield(*response_headers.first).and_yield(*response_headers.to_a.last)
  end

  after { described_class.send(:reset!) }

  describe ".start" do
    it "serializes the invocation before user code can mutate it and extracts the extension context" do
      event = {"message" => "original"}
      digest = described_class.start(event, "request-1")
      event["message"] = "mutated"

      request = requests.first
      expect(request.body).to eq('{"message":"original"}')
      expect(request["lambda-runtime-aws-request-id"]).to eq("request-1")
      expect(request["dd-internal-untraced-request"]).to eq("true")
      expect(digest.trace_id).to eq(123)
      expect(digest.trace_origin).to eq("lambda")
    end

    it "reuses one HTTP connection across invocations" do
      described_class.start({}, "request-1")
      described_class.start({}, "request-2")

      expect(Net::HTTP).to have_received(:new).once
    end
  end

  describe ".finish" do
    it "sends trace and encoded handler error metadata" do
      span = instance_double(Datadog::Tracing::SpanOperation, id: 456)
      error = RuntimeError.new("failure")
      error.set_backtrace(["handler.rb:1"])

      digest = Datadog::Tracing::TraceDigest.new(trace_id: 123, span_id: 456, trace_sampling_priority: 1)
      active_trace = instance_double(Datadog::Tracing::TraceOperation, to_digest: digest)
      allow(Datadog::Tracing).to receive(:active_trace).and_return(active_trace)

      described_class.finish(
        "{\"ok\":false}",
        span: span,
        request_id: "request-2",
        error: error,
        trace_digest: digest,
      )

      request = requests.first
      expect(request.path).to eq("/lambda/end-invocation")
      expect(request.body).to eq('{"ok":false}')
      expect(request["x-datadog-span-id"]).to eq("456")
      expect(request["x-datadog-invocation-error"]).to eq("true")
      codec = Datadog::Core::Utils::Base64Codec
      expect(codec.strict_decode64(request["x-datadog-invocation-error-msg"])).to eq("failure")
      expect(codec.strict_decode64(request["x-datadog-invocation-error-type"])).to eq("RuntimeError")
    end

    it "does not consume a streaming RIC response" do
      stream = StringIO.new("streamed response")
      span = instance_double(Datadog::Tracing::SpanOperation, id: 456)

      described_class.finish([stream, "application/unknown"], span: span, request_id: "request-3")

      expect(requests.first.body).to eq("{}")
      expect(stream.pos).to eq(0)
    end
  end

  describe ".claim_cold_start" do
    it "returns true only once" do
      expect(described_class.claim_cold_start).to be true
      expect(described_class.claim_cold_start).to be false
    end
  end
end
