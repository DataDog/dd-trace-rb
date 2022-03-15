require 'objspace'

module Datadog
  module Profiling
    module WipMemory
      def self.maybe_get_size(object_id)
        begin
          ObjectSpace.memsize_of(ObjectSpace._id2ref(object_id))
        rescue RangeError
          false
        end
      end
    end
  end
end
