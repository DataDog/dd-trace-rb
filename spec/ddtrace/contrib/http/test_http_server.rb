require 'socket'

class TestHTTPServer
  def initialize(host, port)
    @requests = []
    @server = TCPServer.new host, port
    @delay = nil
    reset_next_response
    start_listen_thread
  end

  def start_listen_thread
    @thread = Thread.new do
      while Thread.current.alive? && !@server.closed?
        process_request
      end
    end
  end

  def process_request
    session = @server.accept

    request = []
    while (line = session.gets.strip) != ""
      request << line
    end
    @requests << request

    session.read(requests.last[:headers]["Content-Length"].to_i) if requests.last[:method] == "POST"
    sleep @delay if @delay

    @next_response.each { |line| session.print line }

    session.close
    reset_next_response
  rescue
    nil
  end

  def requests
    @requests.map do |request|
      method, path, http_version = request[0].split(" ", 3)
      {
        method: method,
        path: path,
        http_version: http_version,
        headers: request[1..-1].map { |header| header.split(":", 2).map { |value| value.strip} }.to_h
      }
    end
  end

  def requests_paths
    @requests.map { |request| request[0] }
  end

  def close
    @thread.kill
    @server.close
    @thread.join
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

  def set_response_delay(seconds)
    @delay = seconds
  end
end
