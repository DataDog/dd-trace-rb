module NetworkHelpers
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

  # Returns the trace agent host to use
  #
  # @return [String] agent host
  def agent_host
    ENV['DD_AGENT_HOST']
  end

  # Returns the trace agent port to use
  #
  # @return [Integer] agent port
  def agent_port
    ENV['DD_TRACE_AGENT_PORT']
  end

  # Returns the agent url to use for testing
  #
  # @yield [String] agent url
  def agent_url
    "http://#{agent_host}:#{agent_port}"
  end
end
