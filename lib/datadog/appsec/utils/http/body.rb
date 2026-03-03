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
          def self.parse(body, media_type:)
            return if body.nil?

            body.rewind if body.respond_to?(:rewind) # steep:ignore NoMethod
            # @type var content: ::String?
            content = body.respond_to?(:read) ? body.read : body # steep:ignore NoMethod, IncompatibleAssignment
            body.rewind if body.respond_to?(:rewind) # steep:ignore NoMethod

            return if content.nil? || content.empty?

            if media_type.subtype == 'json' || media_type.subtype.end_with?('+json')
              JSON.parse(content)
            elsif media_type.subtype == 'x-www-form-urlencoded'
              URLEncoded.parse(content)
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
