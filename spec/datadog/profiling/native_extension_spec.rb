require 'datadog/profiling/spec_helper'

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

  describe 'grab_gvl_and_raise' do
    it 'raises the requested exception with the passed in message' do
      expect { described_class::Testing._native_grab_gvl_and_raise(ZeroDivisionError, 'this is a test', nil, true) }
        .to raise_exception(ZeroDivisionError, 'this is a test')
    end

    it 'accepts printf-style string formatting' do
      expect { described_class::Testing._native_grab_gvl_and_raise(ZeroDivisionError, 'divided zero by ', 42, true) }
        .to raise_exception(ZeroDivisionError, 'divided zero by 42')
    end

    it 'limits the exception message to 255 characters' do
      big_message = 'a' * 500

      expect { described_class::Testing._native_grab_gvl_and_raise(ZeroDivisionError, big_message, nil, true) }
        .to raise_exception(ZeroDivisionError, /a{255}\z/)
    end

    context 'when called without releasing the gvl' do
      it 'raises a RuntimeError' do
        expect { described_class::Testing._native_grab_gvl_and_raise(ZeroDivisionError, 'this is a test', nil, false) }
          .to raise_exception(RuntimeError, /called by thread holding the global VM lock/)
      end
    end
  end

  describe 'grab_gvl_and_raise_syserr' do
    it 'raises an exception with the passed in message and errno' do
      expect do
        described_class::Testing._native_grab_gvl_and_raise_syserr(Errno::EINTR::Errno, 'this is a test', nil, true)
      end.to raise_exception(Errno::EINTR, "#{Errno::EINTR.exception.message} - this is a test")
    end

    it 'accepts printf-style string formatting' do
      expect do
        described_class::Testing._native_grab_gvl_and_raise_syserr(Errno::EINTR::Errno, 'divided zero by ', 42, true)
      end.to raise_exception(Errno::EINTR, "#{Errno::EINTR.exception.message} - divided zero by 42")
    end

    it 'limits the caller-provided exception message to 255 characters' do
      big_message = 'a' * 500

      expect do
        described_class::Testing._native_grab_gvl_and_raise_syserr(Errno::EINTR::Errno, big_message, nil, true)
      end.to raise_exception(Errno::EINTR, /.+a{255}\z/)
    end

    context 'when called without releasing the gvl' do
      it 'raises a RuntimeError' do
        expect do
          described_class::Testing._native_grab_gvl_and_raise_syserr(Errno::EINTR::Errno, 'this is a test', nil, false)
        end.to raise_exception(RuntimeError, /called by thread holding the global VM lock/)
      end
    end
  end

  describe 'ddtrace_rb_ractor_main_p' do
    subject(:ddtrace_rb_ractor_main_p) { described_class::Testing._native_ddtrace_rb_ractor_main_p }

    context 'when Ruby has no support for Ractors' do
      before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION >= '3' }

      it { is_expected.to be true }
    end

    context 'when Ruby has support for Ractors' do
      before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION < '3' }

      context 'on the main Ractor' do
        it { is_expected.to be true }
      end

      context 'on a background Ractor' do
        # @ivoanjo: When we initially added this test, our test suite kept deadlocking in CI in a later test (not on
        # this one).
        #
        # It turns out that Ruby 3.0 Ractors seem to have some bug that even running `Ractor.new { 'hello' }.take` will
        # cause a later spec to fail, usually with a (native C) stack with `gc_finalize_deferred`.
        #
        # I was able to see this even on both Linux with 3.0.3 and macOS with 3.0.4. Thus, I decided to skip this
        # spec on Ruby 3.0. We can always run it manually if we change something around this helper; and we have
        # coverage on 3.1+ anyway.
        before { skip 'Ruby 3.0 Ractors are too buggy to run this spec' if RUBY_VERSION.start_with?('3.0.') }

        subject(:ddtrace_rb_ractor_main_p) do
          Ractor.new { Datadog::Profiling::NativeExtension::Testing._native_ddtrace_rb_ractor_main_p }.take
        end

        it { is_expected.to be false }
      end
    end
  end

  describe 'is_current_thread_holding_the_gvl' do
    subject(:is_current_thread_holding_the_gvl) do
      Datadog::Profiling::NativeExtension::Testing._native_is_current_thread_holding_the_gvl
    end

    context 'when current thread is holding the global VM lock' do
      it { is_expected.to be true }
    end

    context 'when current thread is not holding the global VM lock' do
      subject(:is_current_thread_holding_the_gvl) do
        Datadog::Profiling::NativeExtension::Testing._native_release_gvl_and_call_is_current_thread_holding_the_gvl
      end

      it { is_expected.to be false }
    end

    describe 'correctness' do
      let(:ready_queue) { Queue.new }
      let(:background_thread) do
        Thread.new do
          Datadog::Profiling::NativeExtension::Testing._native_install_holding_the_gvl_signal_handler
          ready_queue << true
          i = 0
          loop { (i = (i + 1) % 2) }
        end
      end

      after do
        background_thread.kill
        background_thread.join
      end

      # ruby_thread_has_gvl_p() can return true even when the thread is not holding the global VM lock. See the comments
      # on is_current_thread_holding_the_gvl() for more details. Here we test that our function is accurate in the same
      # situation.
      #
      # Here's how this works:
      # * background_thread installs a signal handler that will call both ruby_thread_has_gvl_p() and
      #   is_current_thread_holding_the_gvl() and return their results
      # * the main testing thread waits until the background thread is executing the dummy infinite loop and then
      #   triggers the signal. Because the main testing thread keeps holding the GVL while it sends the signal to
      #   the background thread, we are guaranteed that the background thread does not have the GVL.
      #
      # @ivoanjo: It's a bit weird but I wanted test coverage for this. Improvements welcome ;)
      it 'returns accurate results when compared to ruby_thread_has_gvl_p' do
        background_thread
        ready_queue.pop

        result = Datadog::Profiling::NativeExtension::Testing
          ._native_trigger_holding_the_gvl_signal_handler_on(background_thread)
        expect(result).to eq(ruby_thread_has_gvl_p: true, is_current_thread_holding_the_gvl: false)
      end
    end
  end

  describe 'enforce_success' do
    context 'when there is no error' do
      it 'does nothing' do
        expect { described_class::Testing._native_enforce_success(0, true) }.to_not raise_error
      end
    end

    context 'when there is an error' do
      let(:have_gvl) { true }

      it 'raises an exception with the passed in errno' do
        expect { described_class::Testing._native_enforce_success(Errno::EINTR::Errno, have_gvl) }
          .to raise_exception(Errno::EINTR, /#{Errno::EINTR.exception.message}.+profiling\.c/)
      end

      context 'when called without the gvl' do
        let(:have_gvl) { false }
        it 'raises an exception with the passed in errno' do
          expect { described_class::Testing._native_enforce_success(Errno::EINTR::Errno, have_gvl) }
            .to raise_exception(Errno::EINTR, /#{Errno::EINTR.exception.message}.+profiling\.c/)
        end
      end
    end
  end
end
