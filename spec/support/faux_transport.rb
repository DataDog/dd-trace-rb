require 'ddtrace/transport/http'

# FauxTransport is a dummy Datadog::Transport that doesn't send data to an agent.
class FauxTransport < Datadog::Transport::HTTP::Client
  def initialize(*); end

  def send_traces(*)
    # Emulate an OK response
    [Datadog::Transport::HTTP::Traces::Response.new(
      Datadog::Transport::HTTP::Adapters::Net::Response.new(
        Net::HTTPResponse.new(1.0, 200, 'OK')
      )
    )]
  end
end
