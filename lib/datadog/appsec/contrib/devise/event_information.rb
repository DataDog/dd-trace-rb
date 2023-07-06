# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Devise
        # Module to extract event information from the resource
        module EventInformation
          UUID_REGEX = /^\h{8}-\h{4}-\h{4}-\h{4}-\h{12}$/.freeze

          SAFE_MODE = 'safe'
          EXTENDED_MODE = 'extended'

          def self.extract(resource, mode)
            event = {}

            return event unless resource

            resource_id = resource.id

            case mode
            when EXTENDED_MODE
              resource_email = resource.email
              resource_username = resource.username

              event[:id] = resource_id if resource_id
              event[:email] = resource_email if resource_email
              event[:username] = resource_username if resource_username
            when SAFE_MODE
              event[:id] = resource_id if resource_id && resource_id.to_s =~ UUID_REGEX
            else
              Datadog.logger.warn(
                "Invalid automated user evenst mode: `#{mode}`. "\
                              'Supported modes are: `safe` and `extended`.'
              )
            end

            event
          end
        end
      end
    end
  end
end
