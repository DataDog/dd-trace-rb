# typed: true

module Datadog
  module Profiling
    module Collectors
      # TODO: BETTER DESCRIPTION
      # Methods prefixed with _native_ are implemented in `collectors_stack.c`
      class Stack
        def serialize
          status, result = self.class._native_serialize(self)

          #[start, finish, encoded_pprof]
        end
      end
    end
  end
end
