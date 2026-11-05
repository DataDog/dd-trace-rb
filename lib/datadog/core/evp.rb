# frozen_string_literal: true

module Datadog
  module Core
    module EVP
      SUBDOMAIN_HEADER_NAME = "X-Datadog-EVP-Subdomain"
      EVENT_PLATFORM_INTAKE_SUBDOMAIN = "event-platform-intake"
      PAYLOAD_SIZE_LIMIT_BYTES = 5 * 1024 * 1024
    end
  end
end
