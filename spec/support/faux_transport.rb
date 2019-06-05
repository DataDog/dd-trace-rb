require 'thread'
require 'ddtrace/transport'
require 'ddtrace/transport/http'

# FauxTransport is a dummy HTTPTransport that doesn't send data to an agent.
class FauxTransport < Datadog::HTTPTransport
  def send(*)
    200 # do nothing, consider it done
  end
end
