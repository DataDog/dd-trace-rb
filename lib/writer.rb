
require 'net/http'


module Datadog
  class Writer

    def initialize(host, port)
      @http = Net::HTTP.new(host, port)
      @headers = {'Content-Type' => 'text/json'}
    end

    def write(spans)
      out = Datadog.encode_spans(spans)

      puts "Sending:"
      puts out

      request = Net::HTTP::Post.new("/spans", @headers)
      request.body = out

      response = @http.request(request)
      puts response

    end

  end
end
