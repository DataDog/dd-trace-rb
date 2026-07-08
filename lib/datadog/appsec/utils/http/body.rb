# frozen_string_literal: true

require 'json'
require 'cgi'

require_relative 'url_encoded'

module Datadog
  module AppSec
    module Utils
      module HTTP
        # Module for handling HTTP body parsing
        module Body
          # Matches Rack's default query bytesize limit to guard against CPU/memory exhaustion.
          DEFAULT_BYTESIZE_LIMIT = 4 * 1024 * 1024

          def self.parse(body, media_type:, bytesize_limit: DEFAULT_BYTESIZE_LIMIT)
            return if body.nil?

            body.rewind if body.respond_to?(:rewind) # steep:ignore NoMethod
            # @type var content: ::String?
            content = body.respond_to?(:read) ? body.read : body # steep:ignore NoMethod, IncompatibleAssignment
            body.rewind if body.respond_to?(:rewind) # steep:ignore NoMethod

            return if content.nil? || content.empty?

            if media_type.subtype == 'json' || media_type.subtype.end_with?('+json')
              JSON.parse(content)
            elsif media_type.subtype == 'x-www-form-urlencoded'
              URLEncoded.parse(content, limit: bytesize_limit)
            end
          rescue => e
            AppSec.telemetry.report(e, description: 'AppSec: Failed to parse body')

            nil
          end
        end
      end
    end
  end
end
