# frozen_string_literal: true

module Datadog
  module AppSec
    module SecurityEngine
      class WAFHandleRegistry
        def initialize(current_handle)
          @current_handle = current_handle

          @counters = Hash.new(0)
          @outdated_handles = []
          @mutex = Mutex.new
        end

        def acquire_current_handle
          @mutex.synchronize do
            @counters[@current_handle] += 1

            @current_handle
          end
        end

        def release_handle(waf_handle)
          @mutex.synchronize do
            @counters[waf_handle] -= 1

            @outdated_handles.reject! do |handle|
              next unless @counters[handle].zero?

              handle.finalize!
              true
            end
          end
        end

        def current_handle=(new_handle)
          @mutex.synchronize do
            @outdated_handles << @current_handle

            @current_handle = new_handle
          end
        end
      end
    end
  end
end
