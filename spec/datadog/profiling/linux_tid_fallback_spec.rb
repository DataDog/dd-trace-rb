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
end
