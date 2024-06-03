# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        # GraphQL integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          QUERY_INTERRUPT = :datadog_appsec_contrib_graphql_query_interrupt
        end
      end
    end
  end
end
