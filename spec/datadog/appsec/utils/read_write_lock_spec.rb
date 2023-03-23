# frozen_string_literal: true

require 'spec_helper'

require 'datadog/appsec/utils/read_write_lock'

RSpec.describe Datadog::AppSec::Utils::ReadWriteLock do
  subject(:read_write_lock) { described_class.new }

  context 'read locks' do
    it 'allows for many readers' do
      rw_lock = read_write_lock
      state = 0
      read_threads = Array.new(3) do
        Thread.new do
          rw_lock.with_rlock do
            expect(state).to eq(0)
          end
        end
      end

      read_threads.each(&:join)
    end

    it 'release the read lock when an exception occurs' do
      rw_lock = read_write_lock
      expect(rw_lock).to receive(:runlock)
      begin
        rw_lock.with_rlock do
          raise StandardError
        end
      rescue
        # do nothing
      end
    end

    it 'writter waits while readers holds the lock' do
      rw_lock = read_write_lock
      state = 0
      queue = Queue.new
      queue2 = Queue.new
      queue3 = Queue.new

      read_thread = Thread.new do
        rw_lock.with_rlock do
          queue << 1
          queue3 << 1
          queue2.pop
        end
      end

      write_thread = Thread.new do
        queue3.pop
        rw_lock.with_lock do
          state = 1
        end
      end

      # The read thead holds the lock and the writter tries to acquire the lock
      queue.pop
      expect(state).to eq(0)

      # we relase the reader lock ans the write locks acquires it and modify state
      queue2 << 1
      read_thread.join
      write_thread.join
      expect(state).to eq(1)
    end
  end

  context 'writer locks' do
    it 'release the write lock when an exception occurs' do
      rw_lock = read_write_lock
      expect(rw_lock).to receive(:unlock)
      begin
        rw_lock.with_lock do
          raise StandardError
        end
      rescue
        # do nothing
      end
    end

    it 'read threads wait for writter lock to be released' do
      rw_lock = read_write_lock
      state = 0
      queue = Queue.new
      queue2 = Queue.new
      queue3 = Queue.new
      queue4 = Queue.new

      read_thread = Thread.new do
        queue2.pop
        expect(state).to eq(0)
        queue3 << 1

        # Wait for writer thread to release the lock. That happens at line 119
        rw_lock.with_rlock do
          expect(state).to eq(1)
        end
      end

      write_thread = Thread.new do
        rw_lock.with_lock do
          queue.pop
          # Allow the reader thread to start running. Check the vale of state before the writer changes it
          queue2 << 1

          # The reader thread has signal that state is 0 and procced to acquire the reader lock.
          # It has to wait because the writer thread holds the lock
          queue3.pop

          # Modify state
          state = 1

          queue4.pop
        end
      end

      # The writter thread holds the lock and modify state
      queue << 1

      # We release the writter lock and assert that state has change inside the reader thread
      queue4 << 1
      read_thread.join
      write_thread.join
    end
  end
end
