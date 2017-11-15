require 'helper'
require 'ddtrace/transport'
require 'ddtrace/writer'
require 'json'

module Datadog
  class WriterTest < Minitest::Test
    def setup
      WebMock.enable!
    end

    def teardown
      WebMock.reset!
      WebMock.disable!
    end

    def test_sampling_feedback_loop
      sampler = Minitest::Mock.new
      writer = Writer.new(priority_sampler: sampler)
      response_body = { 'service:a,env:test' => 0.1, 'service:b,env:test' => 0.5 }.to_json
      v4_endpoint = stub_request(:post, traces_endpoint).to_return(body: response_body)

      sampler.expect(:update, true, [{ 'service:a,env:test' => 0.1, 'service:b,env:test' => 0.5 }])
      writer.send_spans(get_test_traces(1), writer.transport)
      assert_requested(v4_endpoint)
      sampler.verify
    end

    def test_outdated_agent
      sampler = Minitest::Mock.new
      writer = Writer.new(priority_sampler: sampler)
      v4_endpoint = stub_request(:post, traces_endpoint).to_return(status: 404)
      v3_endpoint = stub_request(:post, traces_endpoint(HTTPTransport::V3))

      writer.send_spans(get_test_traces(1), writer.transport)

      assert_requested(v4_endpoint)
      assert_requested(v3_endpoint)
    end

    private

    def traces_endpoint(api_version = HTTPTransport::V4)
      "#{Writer::HOSTNAME}:#{Writer::PORT}/#{api_version}/traces"
    end
  end
end
