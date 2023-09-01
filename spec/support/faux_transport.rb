require 'datadog/tracing/transport/http'

# FauxTransport is a dummy Datadog::Transport that doesn't send data to an agent.
class FauxTransport < Datadog::Tracing::Transport::HTTP::Client
  def initialize(*); end

  def send_traces(*)
    # Emulate an OK response
    [Datadog::Tracing::Transport::HTTP::Traces::Response.new(
      Datadog::Tracing::Transport::HTTP::Adapters::Net::Response.new(
        Net::HTTPResponse.new(1.0, 200, 'OK')
      )
    )]
  end
end
