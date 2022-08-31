class DistributedController < ApplicationController
  # Generates a simple distributed tracing request by requesting
  # the default route from itself. Serializes/deserializes headers,
  # but will reflect the same service name.
  def reflexive
    response = Faraday.get('http://localhost/basic/default')
    render json: { status: response.status }
  end
end
