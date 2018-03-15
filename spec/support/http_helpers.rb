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
end
