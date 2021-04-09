require 'socket'

class TestHTTPServer
  def initialize(host, port)
    @requests = []
    @server = TCPServer.new host, port
    reset_next_response
    start_listen_thread
  end

  def start_listen_thread
    @thread = Thread.new do
      while Thread.current.alive? && session = @server.accept
        request = session.gets
        @requests << request.strip

        @next_response.each { |line| session.print line }

        session.close
        reset_next_response
      end
    end
  end

  def requests
    @requests
  end

  def close
    @thread.kill
    @server.close
  end

  def set_next_response(status:, body:)
    @next_response = [
      "HTTP/1.1 #{status}\r\n",
      "Content-Type: text/plain\r\n",
      "\r\n",
      body,
    ]
  end

  def reset_next_response
    set_next_response(status: 200, body: "Hello world! Time is #{Time.now}")
  end
end
