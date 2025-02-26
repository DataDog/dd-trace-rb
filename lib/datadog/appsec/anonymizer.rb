# frozen_string_literal: true

require 'digest/sha2'

module Datadog
  module AppSec
    # Manual anonymization of the potential PII data
    module Anonymizer
      def self.anonymize(payload)
        "anon_#{Digest::SHA256.hexdigest(payload.to_s)[0, 32]}"
      end
    end
  end
end
