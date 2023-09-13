module NetworkHelpers
  TEST_AGENT_HOST = ENV['DD_TEST_AGENT_HOST'] || 'testagent'
  TEST_AGENT_PORT = ENV['DD_TEST_AGENT_PORT'] || 9126

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
    @test_agent_running ||= check_availability_by_http_request(TEST_AGENT_HOST, TEST_AGENT_PORT)
  end

  # Yields an exclusion allowing WebMock traffic to APM Test Agent given an inputted block that calls webmock
  # function, ie: call_web_mock_function_with_agent_host_exclusions { [options] webmock.disable! options }
  #
  # @yield [Hash] webmock exclusions to call webmock block with
  def call_web_mock_function_with_agent_host_exclusions
    if ENV['DD_AGENT_HOST'] == 'testagent' && test_agent_running?
      yield allow: "http://#{TEST_AGENT_HOST}:#{TEST_AGENT_PORT}"
    else
      yield({})
    end
  end

  # Checks for availability of a Datadog agent or APM Test Agent by trying /info endpoint
  #
  # @return [Boolean] if agent on inputted host / port combo is running
  def check_availability_by_http_request(host, port)
    uri = URI("http://#{host}:#{port}/info")
    request = Net::HTTP::Get.new(uri)
    request[Datadog::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST] = '1'
    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end
    response.is_a?(Net::HTTPSuccess)
  rescue SocketError
    false
  end

  # Gets the Datadog Trace Configuration and returns a comma separated string of key/value pairs.
  #
  # @return [String] Key/Value pairs representing relevant Tracer Configuration
  def parse_tracer_config
    dd_env_variables = ENV.to_h.select { |key, _| key.start_with?('DD_') }
    dd_env_variables['DD_SERVICE'] = dd_env_variables['DD_TEST_EXPECTED_SERVICE']
    dd_env_variables.delete('DD_TEST_EXPECTED_SERVICE')
    dd_env_variables.map { |key, value| "#{key}=#{value}" }.join(',')
  end
end
