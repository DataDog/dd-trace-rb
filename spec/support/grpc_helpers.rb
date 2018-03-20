require 'grpc'

module GRPCHelpers
  def run_service(service_location)
    client = TestService.rpc_stub_class.new(service_location, :this_channel_is_insecure, interceptors: [::GRPC::DatadogClientInterceptor.new])

    server = GRPC::RpcServer.new(interceptors: [::GRPC::DatadogServerInterceptor.new])
    server.add_http2_port(service_location, :this_port_is_insecure)
    server.handle(TestService)

    t = Thread.new { server.run }
    server.wait_till_running

    yield client

    server.stop
    t.join
  end

  def test_message
    TestMessage.new
  end

  class TestMessage
    class << self
      def marshal(_o); ''; end
      def unmarshal(_o); new; end
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