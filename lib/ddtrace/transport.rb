require 'net/http'

module Datadog
  # Transport class that handles the spans delivery to the
  # local trace-agent
  class Transport
    def initialize(host, port)
      @http = Net::HTTP.new(host, port)
      @headers = { 'Content-Type' => 'text/json' }
    end

    def write(spans)
      out = Datadog.encode_spans(spans)

      request = Net::HTTP::Post.new('/spans', @headers)
      request.body = out

      response = @http.request(request)
      puts response
    end
  end
end
