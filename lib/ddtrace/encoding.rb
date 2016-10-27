require 'json'

module Datadog
  # Encoding module that encodes data for the AgentTransport
  module Encoding
    # Encode the given set of spans in the right JSON format
    # so that the agent can parse the list of traces
    def self.encode_spans(traces)
      to_send = []
      traces.each do |trace|
        to_send << trace.map(&:to_hash)
      end
      JSON.dump(to_send)
    end

    def self.encode_services(services)
      JSON.dump(services)
    end
  end
end
