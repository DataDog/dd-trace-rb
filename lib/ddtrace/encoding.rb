require 'json'

module Datadog
  # Encoding module that encodes data for the AgentTransport
  module Encoding
    # Encode the given set of spans in JSON format
    def self.encode_spans(spans)
      hashes = spans.map(&:to_hash)
      JSON.dump(hashes)
    end

    def self.encode_services(services)
      JSON.dump(services)
    end
  end
end
