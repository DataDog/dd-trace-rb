require 'thread'
require 'ddtrace/transport'
require 'ddtrace/transport/http'

# FauxTransport is a dummy HTTPTransport that doesn't send data to an agent.
class FauxTransport < Datadog::HTTPTransport
  def send(*)
    200 # do nothing, consider it done
  end
end

class FauxHTTPService < Datadog::Transport::HTTP::Service
  attr_reader \
    :buffer,
    :status

  def initialize(use_buffer = false)
    @use_buffer = buffer
    @buffer = []
    @client = HTTPClient.new(&method(:add_request))
    @mutex = Mutex.new
    @status = 200
  end

  def open(options = {})
    yield(@client)
  end

  def buffer?
    @use_buffer == true
  end

  def add_request(req)
    @mutex.synchronize { buffer << req } if buffer?
    generate_response
  end

  def set_status!(status)
    @status = status
  end

  private

  def generate_response
    case status
    when 200
      Net::HTTPResponse.new(1.0, status, 'OK')
    when 400
      Net::HTTPResponse.new(1.0, status, 'Bad Request')
    when 401
      Net::HTTPResponse.new(1.0, status, 'Unauthorized')
    when 404
      Net::HTTPResponse.new(1.0, status, 'Not Found')
    when 415
      Net::HTTPResponse.new(1.0, status, 'Unsupported Media Type')
    when 500
      Net::HTTPResponse.new(1.0, status, 'Internal Server Error')
    end
  end

  class HTTPClient
    def initialize(&block)
      @callback = block
    end

    def request(req)
      @callback.call(req)
    end
  end
end
