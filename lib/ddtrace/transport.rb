require 'thread'
require 'net/http'

module Datadog
  # Transport class that handles the spans delivery to the
  # local trace-agent. The class wraps a Net:HTTP instance
  # so that the Transport is thread-safe.
  class HTTPTransport
    # seconds before the transport timeout
    TIMEOUT = 1

    def initialize(hostname, port)
      @headers = { 'Content-Type' => 'text/json' }
      @hostname = hostname
      @port = port
    end

    # send data to the trace-agent; the method is thread-safe
    def send(url, data)
      request = Net::HTTP::Post.new(url, @headers)
      request.body = data

      response = Net::HTTP.start(url.host, url.port, read_timeout: TIMEOUT) { |http| http.request(request) }
      handle_response(response)
    end

    def informational?(code)
      code.between?(100, 199)
    end

    def success?(code)
      code.between?(200, 299)
    end

    def redirect?(code)
      code.between?(300, 399)
    end

    def client_error?(code)
      code.between?(400, 499)
    end

    def server_error?(code)
      code.between?(500, 599)
    end

    # handles the server response; here you can log the trace-agent response
    # or do something more complex to recover from a possible error. This
    # function is handled within the HTTP mutex.synchronize so it's thread-safe.
    def handle_response(response)
      status_code = response.code

      if success?(status_code)
        Datadog::Tracer.log.debug('Payload correctly sent to the trace agent.')
      elsif client_error?(status_code)
        Datadog::Tracer.log.error("Client error: #{response.message}")
      elsif server_error?(status_code)
        Datadog::Tracer.log.error("Server error: #{response.message}")
      end
    end
  end
end
