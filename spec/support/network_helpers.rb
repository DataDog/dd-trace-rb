module NetworkHelpers
  TEST_AGENT_HOST = ENV['DD_AGENT_HOST'] || 'testagent'
  TEST_AGENT_PORT = ENV['DD_TRACE_AGENT_PORT'] || 9126

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

  # Yields an exclusion allowing WebMock traffic to APM Test Agent given an inputted block that calls webmock
  # function, ie: call_web_mock_function_with_agent_host_exclusions { [options] webmock.disable! options }
  #
  # @yield [Hash] webmock exclusions to call webmock block with
  def call_web_mock_function_with_agent_host_exclusions
    yield allow: "http://#{TEST_AGENT_HOST}:#{TEST_AGENT_PORT}"
  end

  # Gets the Datadog Trace Configuration and returns a comma separated string of key/value pairs.
  #
  # @return [String] Key/Value pairs representing relevant Tracer Configuration
  def parse_tracer_config
    dd_env_variables = ENV.to_h.select { |key, _| key.start_with?('DD_') }
    dd_env_variables.map { |key, value| "#{key}=#{value}" }.join(',')
  end
end
