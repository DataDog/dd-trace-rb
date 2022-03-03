# typed: false
require 'datadog/profiling/native_extension'

RSpec.describe Datadog::Profiling::NativeExtension do
  before { skip_if_profiling_not_supported(self) }

  describe '.working?' do
    subject(:working?) { described_class.send(:working?) }

    it { is_expected.to be true }
  end

  describe '.clock_id_for' do
    subject(:clock_id_for) { described_class.clock_id_for(thread) }

    context 'on Linux' do
      before do
        skip 'Test only runs on Linux' unless PlatformHelpers.linux?
      end

      context 'when called with a live thread' do
        let(:thread) { Thread.current }

        it { is_expected.to be_a_kind_of(Integer) }
      end

      context 'when called with a dead thread' do
        let(:thread) { Thread.new {}.tap(&:join) }

        it 'raises an Errno::ESRCH error' do
          # Interestingly enough, it seems like it takes a bit of time to clean up the resources from the dead thread
          # so this is why we use the try_wait_until and try to poke at Ruby to make it decide to go ahead with the
          # cleanup. (I'm actually not sure if the delay is from the Ruby VM even...)

          try_wait_until(attempts: 500, backoff: 0.01) do
            Thread.pass
            GC.start

            begin
              described_class.clock_id_for(thread)
              false
            rescue Errno::ESRCH
              true
            end
          end
        end
      end

      context 'when called with a thread subclass' do
        let(:thread) { Class.new(Thread).new { sleep } }

        after do
          thread.kill
          thread.join
        end

        it { is_expected.to be_a_kind_of(Integer) }
      end

      context 'when called with a Process::Waiter instance' do
        # In Ruby 2.3 to 2.6, `Process.detach` creates a special `Thread` subclass named `Process::Waiter`
        # that is improperly initialized and some operations on it can trigger segfaults, see
        # https://bugs.ruby-lang.org/issues/17807.
        #
        # Thus, let's exercise our code with one of these objects to ensure future changes don't introduce regressions.
        let(:thread) { Process.detach(fork { sleep }) }

        it 'is expected to be a kind of Integer' do
          expect_in_fork { is_expected.to be_a_kind_of(Integer) }
        end
      end

      context 'when called with a non-thread object' do
        let(:thread) { :potato }

        it { expect { clock_id_for }.to raise_error(TypeError) }
      end
    end

    context 'when not on Linux' do
      before do
        skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
      end

      let(:thread) { Thread.current }

      it 'always returns nil' do
        is_expected.to be nil
      end
    end
  end

  describe '.cpu_time_ns_for' do
    subject(:cpu_time_ns_for) { described_class.cpu_time_ns_for(thread) }

    context 'on Linux' do
      before do
        skip 'Test only runs on Linux' unless PlatformHelpers.linux?
      end

      def wait_for_thread_to_die
        # Wait for thread to actually die, as seen by clock_id_for
        try_wait_until(attempts: 500, backoff: 0.01) do
          Thread.pass
          GC.start

          begin
            described_class.clock_id_for(thread)
            false
          rescue Errno::ESRCH
            true
          end
        end
      end

      context 'when called with a live thread' do
        let(:thread) { Thread.current }

        it { is_expected.to be_a_kind_of(Integer) }

        it 'increases between calls for a busy thread' do
          before_time = described_class.cpu_time_ns_for(thread)

          # do some stuff
          GC.start
          Thread.pass

          after_time = described_class.cpu_time_ns_for(thread)

          expect(after_time).to be > before_time
        end
      end

      context 'when called with a dead thread' do
        let(:thread) { Thread.new {}.tap(&:join) }

        before { wait_for_thread_to_die }

        it { is_expected.to be nil }
      end

      context 'when called with a thread that dies between getting the clock_id and getting the cpu time' do
        # This is a bit coupled with the implementation, but we want to check that we correctly handle
        # ::Process.clock_gettime being called with a dead thread, even if the thread was alive when we got the clock_id

        let(:thread) { Thread.new { sleep } }

        before do
          expect(::Process).to receive(:clock_gettime).and_wrap_original do |original, *args|
            thread.kill
            thread.join

            wait_for_thread_to_die

            original.call(*args)
          end
        end

        it { is_expected.to be nil }
      end
    end

    context 'when not on Linux' do
      before do
        skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
      end

      let(:thread) { Thread.current }

      it 'always returns nil' do
        is_expected.to be nil
      end
    end
  end
end
