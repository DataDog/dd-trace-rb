require 'time'
require 'net/http'
require 'spec/support/synchronization_helpers'

module HttpHelpers
  def mock_http_request(options = {})
    http_method = options[:method] || :get
    uri = URI.parse('http://localhost:3000/mock_response')
    body = options[:body] || ''
    status = options[:status] || 200

    # Stub request
    stub = stub_request(http_method, uri).to_return(body: body, status: status)

    # Create the HTTP objects
    http = Net::HTTP.new(uri.host, uri.port)

    if http_method == :get
      request = Net::HTTP::Get.new(uri.request_uri, {})
    elsif http_method == :post
      request = Net::HTTP::Post.new(uri.request_uri, {})
      request.body = {}.to_json
    end

    # Generate response
    { stub: stub, request: request, response: http.request(request) }
  end

  def wait_http_server(server, delay)
    SynchronizationHelpers.try_wait_until(attempts: delay, backoff: 1) do |attempts_left|
      uri = URI(server + '/')
      begin
        res = Net::HTTP.get_response(uri)
        return true if res.code == '200'
      rescue StandardError => e
        Datadog::Logger.log.error("Failed waiting for http server #{e.message}") if attempts_left < 5
      end
    end
  end
end
