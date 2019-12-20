module NetworkHelpers
  def available_endpoint
    "0.0.0.0:#{available_port}"
  end

  def available_port
    server = TCPServer.new('0.0.0.0', 0)
    server.addr[1].tap do
      server.close
    end
  end
end
