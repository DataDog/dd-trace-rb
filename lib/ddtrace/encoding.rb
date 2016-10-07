require 'json'

module Datadog
  module Encoding
    # Encode the given set of spans in JSON format
    def self.encode_spans(spans)
      hashes = spans.map(&:to_hash)
      JSON.dump(hashes)
    end
  end
end
