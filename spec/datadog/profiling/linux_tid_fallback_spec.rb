require 'datadog/profiling/spec_helper'
require 'datadog/profiling/linux_tid_fallback'

RSpec.describe Datadog::Profiling::LinuxTidFallback do
  before { skip_if_profiling_not_supported(self) }

  subject(:linux_tid_fallback) { described_class.new }

  describe '#linux_tid_fallback_for' do
    def linux_tid_fallback_for(thread)
      described_class::Testing._native_linux_tid_fallback_for(linux_tid_fallback, thread)
    end

    context 'when not on Linux' do
      before do
        skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
      end

      it 'always returns -1' do
        expect(linux_tid_fallback_for(Thread.current)).to be(-1)
      end
    end

    context 'when on Linux' do
      before do
        skip 'Test only runs on Linux' unless PlatformHelpers.linux?
        check_for_process_vm_readv
      end

      context 'on Ruby >= 3.1' do
        before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION < '3.1.' }

        # Thread#native_thread_id was added on 3.1
        it 'returns the same as Thread#native_thread_id' do
          all_threads = Thread.list

          expect(all_threads.map(&:native_thread_id)).to eq(all_threads.map { |it| linux_tid_fallback_for(it) })
        end
      end

      it 'returns the same as gettid' do
        expect(linux_tid_fallback_for(Thread.current)).to be described_class::Testing._native_gettid
      end
    end
  end

  describe '.new_if_needed_and_working' do
    subject(:new_if_needed_and_working) { described_class.new_if_needed_and_working }

    context 'when not on Linux' do
      before do
        skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
      end

      it { is_expected.to be nil }
    end

    context 'when on Linux' do
      before do
        skip 'Test only runs on Linux' unless PlatformHelpers.linux?
        check_for_process_vm_readv
      end

      context 'on Ruby >= 3.1' do
        before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION < '3.1.' }

        it { is_expected.to be nil }
      end

      context 'on Ruby < 3.1' do
        before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION >= '3.1.' }

        it { is_expected.to be_an_instance_of described_class }
      end
    end
  end

  # Why is this here? The LinuxTidFallback relies on the process_vm_readv Linux API, which needs special permissions
  # and may be disabled. This is the case with CircleCI, where we usually run our tests.
  #
  # But it's dangerous to skip running specs in CI, since it may mean that we miss breakages. So, this check
  # tries to be very precise: it only skips the specs IF indeed the API is not available + we're on CircleCI.
  # (In case in the future our setup changes and the specs can run again.)
  #
  # It also breaks the specs with a clear error message when the API is not available; as otherwise the failures
  # would be a bit cryptic.
  #
  # Finally, it adds a DD_PROFILING_SKIP_LINUX_TID_FALLBACK_TESTING that folks can use for local testing, in case
  # their setup doesn't provide this API either.
  def check_for_process_vm_readv
    return if Datadog::Profiling::LinuxTidFallback::Testing._native_can_use_process_vm_readv?

    if ENV['CIRCLECI'] == 'true'
      skip "Skipping LinuxTidFallback specs because process_vm_readv doesn't work on CircleCI"
    elsif ENV['DD_PROFILING_SKIP_LINUX_TID_FALLBACK_TESTING'] == 'true'
      skip 'Skipping LinuxTidFallback specs because DD_PROFILING_SKIP_LINUX_TID_FALLBACK_TESTING is set to true'
    else
      raise(
        'Unexpected: Running in system where process_vm_readv seems to be blocked. ' \
        'To skip running these tests set DD_PROFILING_SKIP_LINUX_TID_FALLBACK_TESTING to true.'
      )
    end
  end
end
