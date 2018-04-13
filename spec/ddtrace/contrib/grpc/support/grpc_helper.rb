require 'grpc'

module GRPCHelper
  def run_request_reply
    runner('0.0.0.0:50052') { |c| c.basic(TestMessage.new) }
  end

  def run_client_streamer
    runner('0.0.0.0:50053') { |c| c.stream_from_client([TestMessage.new]) }
  end

  def run_server_streamer
    runner('0.0.0.0:50054') { |c| c.stream_from_server(TestMessage.new) }
  end

  def run_bidi_streamer
    runner('0.0.0.0:50055') { |c| c.stream_both_ways([TestMessage.new]) }
  end

  def runner(address)
    server = GRPC::RpcServer.new
    server.add_http2_port(address, :this_port_is_insecure)
    server.handle(TestService)

    t = Thread.new { server.run }
    server.wait_till_running

    yield TestService.rpc_stub_class.new(address, :this_channel_is_insecure)

    server.stop
    until server.stopped?; end
    t.join
  end

  class TestMessage
    class << self
      def marshal(_o)
        ''
      end

      def unmarshal(_o)
        new
      end
    end
  end

  class TestService
    include GRPC::GenericService

    rpc :basic, TestMessage, TestMessage
    rpc :stream_from_client, stream(TestMessage), TestMessage
    rpc :stream_from_server, TestMessage, stream(TestMessage)
    rpc :stream_both_ways, stream(TestMessage), stream(TestMessage)

    attr_reader :received_metadata

    def initialize(**keywords)
      @trailing_metadata = keywords
      @received_metadata = []
    end

    # provide implementations for each registered rpc interface
    def basic(request, call)
      call.output_metadata.update(@trailing_metadata)
      @received_metadata << call.metadata unless call.metadata.nil?
      TestMessage.new
    end

    def stream_from_client(call)
      call.output_metadata.update(@trailing_metadata)
      call.each_remote_read.each { |r| r }
      TestMessage.new
    end

    def stream_from_server(_request, call)
      call.output_metadata.update(@trailing_metadata)
      [TestMessage.new, TestMessage.new]
    end

    def stream_both_ways(requests, call)
      call.output_metadata.update(@trailing_metadata)
      call.each_remote_read.each { |r| r }
      [TestMessage.new, TestMessage.new]
    end
  end
end
