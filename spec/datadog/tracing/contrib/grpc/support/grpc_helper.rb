require 'grpc'
require 'spec/support/thread_helpers'

if RUBY_VERSION < '2.3'
  require_relative './gen/grpc-1.19.0/test_service_services_pb'
else
  require_relative './gen/test_service_services_pb'
end

module GRPCHelper
  def run_request_reply(address = available_endpoint, client = nil)
    runner(address, client) { |c| c.basic(TestMessage.new) }
  end

  def run_request_reply_error(address = available_endpoint, client = nil)
    runner(address, client) { |c| c.error(TestMessage.new) }
  end

  def run_client_streamer(address = available_endpoint, client = nil)
    runner(address, client) { |c| c.stream_from_client([TestMessage.new]) }
  end

  def run_server_streamer(address = available_endpoint, client = nil)
    runner(address, client) do |c|
      c.stream_from_server(TestMessage.new)
      sleep 0.05
    end
  end

  def run_bidi_streamer(address = available_endpoint, client = nil)
    runner(address, client) do |c|
      c.stream_both_ways([TestMessage.new])
      sleep 0.05
    end
  end

  def runner(address, client)
    # GRPC native threads that are never cleaned up
    server = ThreadHelpers.with_leaky_thread_creation(:grpc) { GRPC::RpcServer.new }

    server.add_http2_port(address, :this_port_is_insecure)
    server.handle(TestService)

    t = Thread.new { server.run }
    server.wait_till_running

    client ||= TestService.rpc_stub_class.new(address, :this_channel_is_insecure)

    yield client
  rescue StandardError => e
    Datadog.logger.debug("GRPC call failed: #{e}")

    raise
  ensure
    server.stop
    until server.stopped?; end
    t.join
  end

  class TestService < GRPCHelper::Testing::Service
    attr_reader :received_metadata

    # rubocop:disable Lint/MissingSuper
    def initialize(**keywords)
      @trailing_metadata = keywords
      @received_metadata = []
    end
    # rubocop:enable Lint/MissingSuper

    def basic(_request, call)
      call.output_metadata.update(@trailing_metadata)
      @received_metadata << call.metadata unless call.metadata.nil?
      GRPCHelper::TestMessage.new
    end

    def error(_request, call)
      raise GRPC::BadStatus.new_status_exception(GRPC::Core::StatusCodes::INVALID_ARGUMENT)
    end

    def stream_from_client(call)
      call.output_metadata.update(@trailing_metadata)
      call.each_remote_read.each {} # Consume data
      GRPCHelper::TestMessage.new
    end

    def stream_from_server(_request, call)
      call.output_metadata.update(@trailing_metadata)
      [GRPCHelper::TestMessage.new, GRPCHelper::TestMessage.new]
    end

    def stream_both_ways(_requests, call)
      call.output_metadata.update(@trailing_metadata)
      call.each_remote_read.each {} # Consume data
      [GRPCHelper::TestMessage.new, GRPCHelper::TestMessage.new]
    end
  end
end
