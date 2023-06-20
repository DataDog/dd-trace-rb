module NetworkHelpers
  TEST_AGENT_HOST = ENV['DD_TEST_AGENT_HOST']
  TEST_AGENT_PORT = ENV['DD_TEST_AGENT_PORT']

  # Returns a TCP "host:port" endpoint currently available
  # for listening in the local machine
  #
  # @return [String] "host:port" available for listening
  def available_endpoint
    "0.0.0.0:#{available_port}"
  end

  # Finds a TCP port currently available
  # for listening in the local machine
  #
  # @return [Integer] port available for listening
  def available_port
    server = TCPServer.new('0.0.0.0', 0)
    server.addr[1].tap do
      server.close
    end
  end

  def test_agent_running?
    @test_agent_running ||= ENV['DD_TEST_AGENT_HOST'] 
      && ENV['DD_TEST_AGENT_PORT'] 
      && check_availability_by_http_request(TEST_AGENT_HOST, TEST_AGENT_PORT)
  end

  def call_web_mock_function_with_agent_host_exclusions
    if ENV['DD_TEST_AGENT_HOST'] && ENV['DD_TEST_AGENT_PORT'] && test_agent_running?
      yield allow: "http://#{TEST_AGENT_HOST}:#{TEST_AGENT_PORT}"
    else
      yield
    end
  end

  # Checks for availability of a Datadog agent or APM Test Agent by trying /info endpoint
  #
  # @return [Boolean] if agent on inputted host / port combo is running
  def check_availability_by_http_request(host, port)
    uri = URI("http://#{host}:#{port}/info")
    response = Net::HTTP.get_response(uri)
    response.is_a?(Net::HTTPSuccess)
  rescue SocketError
    false
  end
end
