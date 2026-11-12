# frozen_string_literal: true

module Datadog
  module Profiling
    module Miteruby
      class VirelSerializer
        class Recording
          attr_reader :bytes

          def initialize(bytes)
            @bytes = bytes.freeze
          end

          def format
            :virel
          end
        end

        def prepare_serialize
          self.class._native_prepare_serialize(self)
        end

        def serialize
          start, finish, bytes, stats = self.class._native_serialize(self)
          [start, finish, Recording.new(bytes), stats]
        end

        def serialize!
          _start, _finish, recording = serialize
          recording
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
