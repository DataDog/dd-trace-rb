# frozen_string_literal: true

module Datadog
  module Core
    module Transport
      module HTTP
        module Adapters
          class Native
            # Counts the native calls in flight, so that something that must not overlap them can wait for them
            # to finish (and keep new ones from starting).
            #
            # Used twice:
            # * one process-wide instance is {#pause}d around a `fork`: the tokio runtime shared by all the native
            #   clients must not be stopped while any of them is sending;
            # * one instance per adapter is {#close}d before its native client is released: the native layer
            #   does not protect a client against being closed during a send.
            #
            # Only wrap the native call itself: a thread inside {#track} must not wait for the guard to be paused
            # or closed (it would wait for itself).
            #
            # @api private
            class InFlight
              # Raised by {#track} once the guard was closed.
              class Closed < StandardError
              end

              def initialize
                @mutex = Mutex.new
                @condition = ConditionVariable.new
                @active = 0
                @pauses = 0
                @closed = false
              end

              # Runs the block as one call in flight. Waits while the guard is paused.
              #
              # @raise [Closed] if the guard is closed
              def track
                @mutex.synchronize do
                  @condition.wait(@mutex) while @pauses > 0 && !@closed
                  raise Closed, "closed" if @closed
                  @active += 1
                end

                begin
                  yield
                ensure
                  @mutex.synchronize do
                    @active -= 1
                    @condition.broadcast if @active == 0
                  end
                end
              end

              # Waits until nothing is in flight, and keeps new calls waiting until a matching {#resume}.
              # Pauses stack: concurrent forks each pause and resume the guard.
              def pause
                @mutex.synchronize do
                  @pauses += 1
                  @condition.wait(@mutex) until @active == 0
                end

                nil
              end

              # Undoes one {#pause}. Does nothing if the guard is not paused: a failure in a "before fork" step can
              # leave the "after fork" steps without a matching pause.
              def resume
                @mutex.synchronize do
                  @pauses -= 1 if @pauses > 0
                  @condition.broadcast
                end

                nil
              end

              # Waits until nothing is in flight and makes any later {#track} raise {Closed}.
              #
              # @return [Boolean] false if it was already closed
              def close
                @mutex.synchronize do
                  return false if @closed

                  @closed = true
                  @condition.broadcast
                  @condition.wait(@mutex) until @active == 0
                end

                true
              end
            end
          end
        end
      end
    end
  end
end
