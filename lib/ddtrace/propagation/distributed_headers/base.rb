require 'ddtrace/configuration'
require 'ddtrace/span'
require 'ddtrace/ext/priority'

module Datadog
  module DistributedHeaders
    # Base provides common methods for distributed header helper classes
    module Base
      def clamp_sampling_priority(sampling_priority)
        # B3 doesn't have our -1 (USER_REJECT) and 2 (USER_KEEP) priorities so convert to acceptable 0/1
        if sampling_priority < 0
          sampling_priority = Ext::Priority::AUTO_REJECT
        elsif sampling_priority > 1
          sampling_priority = Ext::Priority::AUTO_KEEP
        end

        sampling_priority
      end
    end
  end
end
