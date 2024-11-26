require "datadog/profiling/spec_helper"
require "datadog/profiling/native_extension"

RSpec.describe Datadog::Profiling::NativeExtension do
  before { skip_if_profiling_not_supported(self) }

  describe ".working?" do
    subject(:working?) { described_class.send(:working?) }

    it { is_expected.to be true }
  end

  describe "grab_gvl_and_raise" do
    it "raises the requested exception with the passed in message" do
      expect { described_class::Testing._native_grab_gvl_and_raise(ZeroDivisionError, "this is a test", nil, true) }
        .to raise_exception(ZeroDivisionError, "this is a test")
    end

    it "accepts printf-style string formatting" do
      expect { described_class::Testing._native_grab_gvl_and_raise(ZeroDivisionError, "divided zero by ", 42, true) }
        .to raise_exception(ZeroDivisionError, "divided zero by 42")
    end

    it "limits the exception message to 255 characters" do
      big_message = "a" * 500

      expect { described_class::Testing._native_grab_gvl_and_raise(ZeroDivisionError, big_message, nil, true) }
        .to raise_exception(ZeroDivisionError, /a{255}\z/)
    end

    context "when called without releasing the gvl" do
      it "raises a RuntimeError" do
        expect { described_class::Testing._native_grab_gvl_and_raise(ZeroDivisionError, "this is a test", nil, false) }
          .to raise_exception(RuntimeError, /called by thread holding the global VM lock/)
      end
    end
  end

  describe "grab_gvl_and_raise_syserr" do
    it "raises an exception with the passed in message and errno" do
      expect do
        described_class::Testing._native_grab_gvl_and_raise_syserr(Errno::EINTR::Errno, "this is a test", nil, true)
      end.to raise_exception(Errno::EINTR, "#{Errno::EINTR.exception.message} - this is a test")
    end

    it "accepts printf-style string formatting" do
      expect do
        described_class::Testing._native_grab_gvl_and_raise_syserr(Errno::EINTR::Errno, "divided zero by ", 42, true)
      end.to raise_exception(Errno::EINTR, "#{Errno::EINTR.exception.message} - divided zero by 42")
    end

    it "limits the caller-provided exception message to 255 characters" do
      big_message = "a" * 500

      expect do
        described_class::Testing._native_grab_gvl_and_raise_syserr(Errno::EINTR::Errno, big_message, nil, true)
      end.to raise_exception(Errno::EINTR, /.+a{255}\z/)
    end

    context "when called without releasing the gvl" do
      it "raises a RuntimeError" do
        expect do
          described_class::Testing._native_grab_gvl_and_raise_syserr(Errno::EINTR::Errno, "this is a test", nil, false)
        end.to raise_exception(RuntimeError, /called by thread holding the global VM lock/)
      end
    end
  end

  describe "ddtrace_rb_ractor_main_p" do
    subject(:ddtrace_rb_ractor_main_p) { described_class::Testing._native_ddtrace_rb_ractor_main_p }

    context "when Ruby has no support for Ractors" do
      before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION >= "3" }

      it { is_expected.to be true }
    end

    context "when Ruby has support for Ractors" do
      before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION < "3" }

      context "on the main Ractor" do
        it { is_expected.to be true }
      end

      context "on a background Ractor", ractors: true do
        # @ivoanjo: When we initially added this test, our test suite kept deadlocking in CI in a later test (not on
        # this one).
        #
        # It turns out that Ruby 3.0 Ractors seem to have some bug that even running `Ractor.new { 'hello' }.take` will
        # cause a later spec to fail, usually with a (native C) stack with `gc_finalize_deferred`.
        #
        # I was able to see this even on both Linux with 3.0.3 and macOS with 3.0.4. Thus, I decided to skip this
        # spec on Ruby 3.0. We can always run it manually if we change something around this helper; and we have
        # coverage on 3.1+ anyway.
        before { skip "Ruby 3.0 Ractors are too buggy to run this spec" if RUBY_VERSION.start_with?("3.0.") }

        subject(:ddtrace_rb_ractor_main_p) do
          Ractor.new { Datadog::Profiling::NativeExtension::Testing._native_ddtrace_rb_ractor_main_p }.take
        end

        it { is_expected.to be false }
      end
    end
  end

  describe "is_current_thread_holding_the_gvl" do
    subject(:is_current_thread_holding_the_gvl) do
      Datadog::Profiling::NativeExtension::Testing._native_is_current_thread_holding_the_gvl
    end

    context "when current thread is holding the global VM lock" do
      it { is_expected.to be true }
    end

    context "when current thread is not holding the global VM lock" do
      subject(:is_current_thread_holding_the_gvl) do
        Datadog::Profiling::NativeExtension::Testing._native_release_gvl_and_call_is_current_thread_holding_the_gvl
      end

      it { is_expected.to be false }
    end

    describe "correctness", :memcheck_valgrind_skip do
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
      it "returns accurate results when compared to ruby_thread_has_gvl_p" do
        background_thread
        ready_queue.pop

        result = Datadog::Profiling::NativeExtension::Testing
          ._native_trigger_holding_the_gvl_signal_handler_on(background_thread)
        expect(result).to eq(ruby_thread_has_gvl_p: true, is_current_thread_holding_the_gvl: false)
      end
    end
  end

  describe "enforce_success" do
    context "when there is no error" do
      it "does nothing" do
        expect { described_class::Testing._native_enforce_success(0, true) }.to_not raise_error
      end
    end

    context "when there is an error" do
      let(:have_gvl) { true }

      it "raises an exception with the passed in errno" do
        expect { described_class::Testing._native_enforce_success(Errno::EINTR::Errno, have_gvl) }
          .to raise_exception(Errno::EINTR, /#{Errno::EINTR.exception.message}.+profiling\.c/)
      end

      context "when called without the gvl" do
        let(:have_gvl) { false }
        it "raises an exception with the passed in errno" do
          expect { described_class::Testing._native_enforce_success(Errno::EINTR::Errno, have_gvl) }
            .to raise_exception(Errno::EINTR, /#{Errno::EINTR.exception.message}.+profiling\.c/)
        end
      end
    end
  end

  describe "safe_object_info" do
    let(:object_to_inspect) { "Hey, I'm a string!" }

    subject(:safe_object_info) { described_class::Testing._native_safe_object_info(object_to_inspect) }

    context "on a Ruby with rb_obj_info" do
      before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION.start_with?("2.5", "3.3") }

      it "returns a string with information about the object" do
        expect(safe_object_info).to eq "T_STRING"
      end
    end

    context "on a Ruby without rb_obj_info" do
      before { skip "Behavior does not apply to current Ruby version" unless RUBY_VERSION.start_with?("2.5", "3.3") }

      it "returns a placeholder string and does not otherwise fail" do
        expect(safe_object_info).to eq "(No rb_obj_info for current Ruby)"
      end
    end
  end
end
