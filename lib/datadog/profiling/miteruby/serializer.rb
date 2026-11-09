# frozen_string_literal: true

module Datadog
  module Profiling
    module Miteruby
      class Serializer
        def serialize
          self.class._native_serialize(self)
        end

        def serialize!
          _start, _finish, encoded_profile = serialize
          encoded_profile
        end

        def reset_after_fork
          self.class._native_reset_after_fork(self)
        end

        def stats
          self.class._native_stats(self)
        end
      end
    end
  end
end
