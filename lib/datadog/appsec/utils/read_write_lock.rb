# frozen_string_literal: true

module Datadog
  module AppSec
    module Utils
      # Simple implentation for a fair read write lock
      # It allows for as many concurrent readers but only one concurrent writer.
      # To avoid the writer thread being exhausted, once a writer thread has signaled that it wants to acquire the lock,
      # no more reader threads can acquire the lock.
      # The new reader threads will wait for the writer thread to finish.
      class ReadWriteLock
        def initialize
          @reader_mutex    = Mutex.new
          @reader_q        = ConditionVariable.new
          @reader_count    = 0
          @reader_releases = 0

          @writer_mutex    = Mutex.new
          @writer_q        = ConditionVariable.new
          @writter         = false
        end

        def with_rlock
          rlock
          yield
        ensure
          runlock
        end

        def with_lock
          lock
          yield
        ensure
          unlock
        end

        def rlock
          @reader_mutex.synchronize do
            @reader_count += 1

            writter = false

            @writer_mutex.synchronize do
              writter = @writter
            end

            @reader_q.wait(@reader_mutex) if writter
          end
        end

        def runlock
          @reader_mutex.synchronize do
            @reader_releases += 1

            @writer_mutex.synchronize { @writer_q.signal } if @reader_releases == @reader_count
          end
        end

        def lock
          @writer_mutex.synchronize do
            @writer_q.wait(@writer_mutex) while (@reader_releases != @reader_count) || @writter

            @writter = true
          end
        end

        def unlock
          @writer_mutex.synchronize do
            @writter = false
            @writer_q.signal
          end

          @reader_mutex.synchronize { @reader_q.broadcast }
        end
      end
    end
  end
end
