# frozen_string_literal: true

require_relative "configuration"

# Global namespace that includes all Datadog functionality.
# @public_api
module Datadog
  module Core
    module Extensions
      def self.extended(base)
        base.extend(Core::Configuration)
      end
    end
  end
end
