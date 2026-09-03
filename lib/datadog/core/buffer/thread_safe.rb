# frozen_string_literal: true

require_relative "random"

module Datadog
  module Core
    module Buffer
      # Buffer that stores objects, has a maximum size, and
      # can be safely used concurrently on any environment.
      #
      # This implementation uses a {Mutex} around public methods, incurring
      # overhead in order to ensure thread-safety.
      #
      # This is implementation is recommended for non-CRuby environments.
      # If using CRuby, {Datadog::Core::Buffer::CRuby} is a faster implementation with minimal compromise.
      class ThreadSafe < Random
        def initialize(max_size)
          super

          @mutex = Mutex.new
        end

        def push(item)
          synchronize { super }
        end

        def concat(items)
          synchronize { super }
        end

        def length
          synchronize { super }
        end

        def empty?
          synchronize { super }
        end

        def pop
          synchronize { super }
        end

        def close
          synchronize { super }
        end

        def synchronize(&block)
          @mutex.synchronize(&block)
        end
      end
    end
  end
end
