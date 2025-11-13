# frozen_string_literal: true

module Datadog
  module OpenFeature
    # A namespace for binding code
    module Binding
      ResolutionDetails = Struct.new(
        :value,
        :reason,
        :variant,
        :error_code,
        :error_message,
        :flag_metadata,
        :allocation_key,
        :do_log,
        :extra_logging,
        keyword_init: true
      ) do
        # Check if this is an error result
        def error?
          !error_code.nil?
        end


        # Ruby-friendly method name for logging flag
        def log?
          do_log
        end
        
        # Keep do_log as an alias for backwards compatibility
        alias_method :do_log?, :log?
      end
    end
  end
end
