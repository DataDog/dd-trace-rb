# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Support
        # A basic User model mock sufficient for devise testing
        DeviseUserMock = Struct.new(:id, :uuid, :email, :username, :persisted, keyword_init: true) do
          alias_method :persisted?, :persisted
        end
      end
    end
  end
end
