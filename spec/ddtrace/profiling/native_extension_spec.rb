# typed: false
require 'ddtrace/profiling/native_extension'

RSpec.describe Datadog::Profiling::NativeExtension do
  before do
    skip('Profiling not supported on JRuby') if PlatformHelpers.jruby?

    begin
      require "ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
    rescue LoadError
      raise 'Profiling native extension does not seem to be compiled. ' \
        'Try running `bundle exec rake compile` before running this test.'
    end
  end

  describe '.working?' do
    subject(:working?) { described_class.send(:working?) }

    it { is_expected.to be true }
  end

  describe '.clock_id_for' do
    subject(:clock_id_for) { described_class.clock_id_for(thread) }

    context 'on Linux' do
      before do
        skip 'Test only runs on Linux' unless RUBY_PLATFORM.include?('linux')
      end

      context 'when called with a live thread' do
        let(:thread) { Thread.current }

        it { is_expected.to be_a_kind_of(Integer) }
      end

      context 'when called with a dead thread' do
        let(:thread) { Thread.new {}.tap(&:join) }

        # This one is kinda weird, but I don't make the rules here ;)
        it { is_expected.to be_a_kind_of(Integer) }
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
        skip 'Test only applies when not on Linux' if RUBY_PLATFORM.include?('linux')
      end

      let(:thread) { Thread.current }

      it 'always returns nil' do
        is_expected.to be nil
      end
    end
  end
end
