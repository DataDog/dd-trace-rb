# frozen_string_literal: true

module Datadog
  module AppSec
    # this module encapsulates functions for handling actions that libddawf returns
    module ActionHandler
      module_function

      def handle(type, action_params)
        case type
        when 'block_request' then block_request(action_params)
        when 'redirect_request' then redirect_request(action_params)
        when 'generate_stack' then generate_stack(action_params)
        when 'generate_schema' then generate_schema(action_params)
        when 'monitor' then monitor(action_params)
        else
          Datadog.logger.error "Unknown action type: #{type}"
        end
      end

      def block_request(action_params)
        throw(Datadog::AppSec::Ext::INTERRUPT, action_params)
      end

      def redirect_request(action_params)
        throw(Datadog::AppSec::Ext::INTERRUPT, action_params)
      end

      def generate_stack(_action_params); end

      def generate_schema(_action_params); end

      def monitor(_action_params); end
    end
  end
end
