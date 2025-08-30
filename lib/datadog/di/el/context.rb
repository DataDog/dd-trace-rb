# frozen_string_literal: true

module Datadog
  module DI
    module EL
      # Contains local and instance variables used when evaluating
      # expressions in DI Expression Language.
      #
      # @api private
      class Context
        def initialize(locals:, target:)
          @locals = locals
          @target = target
        end

        attr_reader :locals
        attr_reader :target

        def fetch(var_name)
          # TODO this should be a bad reference?
          return nil unless locals
          locals[var_name.to_sym]
        end

        def fetch_ivar(var_name)
          target.instance_variable_get(var_name)
        end
      end
    end
  end
end
