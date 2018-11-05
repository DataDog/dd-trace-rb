require 'time'
require 'spec/support/synchronization_helpers'
require 'addressable'
require 'http'

module HttpHelpers
  def mock_http_request(options = {})
    http_method = options[:method] || :get
    uri = Addressable::URI.parse('http://localhost:3000/mock_response')
    body = options[:body] || ''
    status = options[:status] || 200

    # Stub request
    stub = stub_request(http_method, uri).to_return(body: body, status: status)

    if http_method == :get
      response = HTTP.get(uri.to_s, {})
    elsif http_method == :post
      response = HTTP.post(uri.to_s, {})
    end

    # Generate response
    { stub: stub, response: response }
  end

  def wait_http_server(server, delay)
    SynchronizationHelpers.try_wait_until(attempts: delay, backoff: 1) do |attempts_left|
      uri = URI(server + '/')
      begin
        res = Net::HTTP.get_response(uri)
        return true if res.code == '200'
      rescue StandardError => e
        Datadog::Tracer.log.error("Failed waiting for http server #{e.message}") if attempts_left < 5
      end
    end
  end
end
