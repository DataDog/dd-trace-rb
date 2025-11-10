# frozen_string_literal: true

module Datadog
  module OpenFeature
    # A namespace for binding code
    module Binding
      class ResolutionDetails
        attr_accessor :value, :reason, :variant, :error_code, :error_message, 
                      :flag_metadata, :allocation_key, :do_log, :extra_logging

        def initialize(value: nil, reason: nil, variant: nil, error_code: nil, 
                       error_message: nil, flag_metadata: nil, allocation_key: nil, 
                       do_log: nil, extra_logging: nil)
          @value = value
          @reason = reason
          @variant = variant
          @error_code = error_code
          @error_message = error_message
          @flag_metadata = flag_metadata
          @allocation_key = allocation_key
          @do_log = do_log
          @extra_logging = extra_logging
        end
      end
    end
  end
end
