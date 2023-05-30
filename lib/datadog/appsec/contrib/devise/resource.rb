# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Devise
        # Class to encpasulate extracting information from a Devise resource
        # TODO: Very barebone implementation. Improve before relase
        #   - Check Devise configuration to infer used value to log in
        class Resource
          def initialize(resource)
            @resource = resource
          end

          def id
            @resource.try(:id)
          end

          def email
            @resource.try(:email)
          end

          def username
            @resource.try(:username)
          end
        end
      end
    end
  end
end
