# frozen_string_literal: true

module Datadog
  module AppSec
    # this module encapsulates functions for handling actions that libddawf returns
    module ActionsHandler
      module_function

      def handle(actions_hash)
        # handle actions according their precedence
        # stack and schema generation should be done before we throw an interrupt signal
        generate_stack(actions_hash['generate_stack']) if actions_hash.key?('generate_stack')
        generate_schema(actions_hash['generate_schema']) if actions_hash.key?('generate_schema')
        redirect_request(actions_hash['redirect_request']) if actions_hash.key?('redirect_request')
        block_request(actions_hash['block_request']) if actions_hash.key?('block_request')
      end

      def block_request(action_params)
        throw(Datadog::AppSec::Ext::INTERRUPT, action_params)
      end

      def redirect_request(action_params)
        throw(Datadog::AppSec::Ext::INTERRUPT, action_params)
      end

      def generate_stack(_action_params); end

      def generate_schema(_action_params); end
    end
  end
end
