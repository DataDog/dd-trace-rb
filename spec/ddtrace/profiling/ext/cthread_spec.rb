require 'spec_helper'
require 'ddtrace/profiling'
require 'ddtrace/profiling/spec_helper'

if Datadog::Profiling::Ext::CPU.supported?
  require 'ddtrace/profiling/ext/cthread'

  RSpec.describe Datadog::Profiling::Ext::CThread do
    subject(:thread) do
      thread_class.new(&block).tap do
        # Give thread a chance to start,
        # which will set native IDs.
        @thread_started = true
        sleep(0.05)
      end
    end

    let(:block) { proc { loop { sleep(1) } } }

    let(:thread_class_with_instrumentation) do
      expect(::Thread.ancestors).to_not include(described_class)

      klass = ::Thread.dup
      klass.send(:prepend, described_class)
      klass
    end

    let(:thread_class_missing_instrumentation) do
      expect(::Thread.ancestors).to_not include(described_class)

      klass = ::Thread.dup

      # keep copy of original initialize method, useful when we want to simulate a thread where our extension hasn't
      # been initialized (e.g. a thread created before the extension was added)
      klass.send(:alias_method, :original_initialize, :initialize)

      # Add the module under test (Ext::CThread)
      klass.send(:prepend, described_class)

      # Add a module that skips over the module under test's initialize changes
      skip_instrumentation = Module.new do
        def initialize(*args, &block)
          original_initialize(*args, &block) # directly call original initialize, skipping the one in Ext::CThread
        end
      end
      klass.send(:prepend, skip_instrumentation)

      klass
    end

    let(:thread_class) { thread_class_with_instrumentation }

    # Kill any spawned threads
    after do
      if instance_variable_defined?(:@thread_started) && @thread_started
        thread.kill
        thread.join
      end
    end

    shared_context 'with main thread' do
      let(:thread_class) { ::Thread }

      def on_main_thread
        # Patch thread in a fork so we don't modify the original Thread class
        expect_in_fork do
          thread_class.send(:prepend, described_class)
          yield
        end

        # Ensure the patch didn't leak out of the fork.
        expect(::Thread).to_not be_a_kind_of(described_class)
      end
    end

    describe 'prepend' do
      let(:thread_class) { ::Thread.dup }

      before { allow(thread_class).to receive(:current).and_return(thread) }

      it 'sets native thread IDs on current thread' do
        # Skip verification because the thread will not have been patched with the method yet
        without_partial_double_verification do
          expect(thread).to receive(:update_native_ids)
          thread_class.send(:prepend, described_class)
        end
      end
    end

    describe '::new' do
      it 'has native thread IDs available' do
        is_expected.to have_attributes(
          native_thread_id: kind_of(Integer),
          cpu_time: kind_of(Float)
        )
        expect(thread.send(:clock_id)).to be_kind_of(Integer)
      end

      it 'correctly forwards all received arguments to the passed proc' do
        received_args = nil
        received_kwargs = nil

        thread_class.new(1, 2, 3, four: 4, five: 5) do |*args, **kwargs|
          received_args = args
          received_kwargs = kwargs
        end.join

        expect(received_args).to eq [1, 2, 3]
        expect(received_kwargs).to eq(four: 4, five: 5)
      end
    end

    describe '#native_thread_id' do
      subject(:native_thread_id) { thread.native_thread_id }

      it { is_expected.to be_a_kind_of(Integer) }

      context 'main thread' do
        context 'when forked' do
          it 'returns a new native thread ID' do
            # Get main thread native ID
            original_native_thread_id = thread.native_thread_id

            expect_in_fork do
              # Expect main thread native ID to not change
              expect(thread.native_thread_id).to be_a_kind_of(Integer)
              expect(thread.native_thread_id).to eq(original_native_thread_id)
            end
          end
        end
      end
    end

    describe '#clock_id' do
      subject(:clock_id) { thread.send(:clock_id) }

      it { is_expected.to be_a_kind_of(Integer) }

      context 'main thread' do
        include_context 'with main thread'

        context 'when forked' do
          it 'returns a new clock ID' do
            on_main_thread do
              # Get main thread clock ID
              original_clock_id = thread_class.current.send(:clock_id)

              expect_in_fork do
                # Expect main thread clock ID to change (to match fork's main thread)
                expect(thread_class.current.send(:clock_id)).to be_a_kind_of(Integer)
                expect(thread_class.current.send(:clock_id)).to_not eq(original_clock_id)
              end
            end
          end
        end
      end
    end

    describe '#cpu_time' do
      subject(:cpu_time) { thread.cpu_time }

      context 'when clock ID' do
        context 'is not available' do
          let(:thread_class) { thread_class_missing_instrumentation }

          it { is_expected.to be nil }

          it 'does not define the @clock_id instance variable' do
            cpu_time

            expect(thread.instance_variable_defined?(:@clock_id)).to be false
          end
        end

        context 'is available' do
          let(:clock_id) { double('clock ID') }

          before { allow(thread).to receive(:clock_id).and_return(clock_id) }

          if Process.respond_to?(:clock_gettime)
            let(:cpu_time_measurement) { double('cpu time measurement') }

            context 'when not given a unit' do
              it 'gets time in CPU seconds' do
                expect(Process)
                  .to receive(:clock_gettime)
                  .with(clock_id, :float_second)
                  .and_return(cpu_time_measurement)

                is_expected.to be cpu_time_measurement
              end
            end

            context 'given a unit' do
              subject(:cpu_time) { thread.cpu_time(unit) }

              let(:unit) { double('unit') }

              it 'gets time in specified unit' do
                expect(Process)
                  .to receive(:clock_gettime)
                  .with(clock_id, unit)
                  .and_return(cpu_time_measurement)

                is_expected.to be cpu_time_measurement
              end
            end
          else
            context 'but #clock_gettime is not' do
              it { is_expected.to be nil }
            end
          end
        end
      end

      context 'main thread' do
        include_context 'with main thread'

        context 'when forked' do
          it 'returns a CPU time' do
            on_main_thread do
              expect(thread_class.current.cpu_time).to be_a_kind_of(Float)

              expect_in_fork do
                expect(thread_class.current.cpu_time).to be_a_kind_of(Float)
              end
            end
          end
        end
      end
    end

    describe '#cpu_time_instrumentation_installed?' do
      it do
        expect(thread.cpu_time_instrumentation_installed?).to be true
      end

      context 'when our custom initialize block did not run' do
        let(:thread_class) { thread_class_missing_instrumentation }

        it do
          expect(thread.cpu_time_instrumentation_installed?).to be false
        end
      end
    end

    context 'Process::Waiter crash regression tests' do
      let(:process_waiter_thread) do
        Process.detach(fork {})
        Thread.list.find { |thread| thread.instance_of?(Process::Waiter) }
      end

      describe 'the crash' do
        # Let's not get surprised if this shows up in other Ruby versions

        it 'does not affect Ruby < 2.3 nor Ruby >= 2.7' do
          unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3') &&
                 Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7')
            skip 'Test case only applies to Ruby < 2.3 or Ruby >= 2.7'
          end

          with_profiling_extensions_in_fork do
            expect(process_waiter_thread.instance_variable_get(:@hello)).to be nil
          end
        end

        it 'affects Ruby >= 2.3 and < 2.7' do
          unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.3') &&
                 Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7')
            skip 'Test case only applies to Ruby >= 2.3 and < 2.7'
          end

          with_profiling_extensions_in_fork(
            fork_expectations: proc do |status, stderr|
              expect(Signal.signame(status.termsig)).to eq 'ABRT'
              expect(stderr).to include('[BUG] Segmentation fault')
            end
          ) do
            process_waiter_thread.instance_variable_get(:@hello)
          end
        end
      end

      describe '#native_thread_id' do
        it 'can be read without crashing the Ruby VM' do
          with_profiling_extensions_in_fork do
            expect(process_waiter_thread.native_thread_id).to be nil
          end
        end
      end
    end
  end

  RSpec.describe Datadog::Profiling::Ext::WrapThreadStartFork do
    let(:thread_class) do
      expect(Thread.singleton_class.ancestors).to_not include(described_class)

      klass = ::Thread.dup
      klass.send(:prepend, Datadog::Profiling::Ext::CThread)
      klass.singleton_class.send(:prepend, described_class)
      klass
    end

    describe '#start' do
      it 'starts a new thread' do
        new_thread = nil

        thread_class.start do
          new_thread = Thread.current
        end.join

        expect(new_thread).to_not be Thread.current
      end

      it 'sets up the CPU time instrumentation before running user code in the thread' do
        ran_assertion = false

        thread_class.start do
          expect(Thread.current.cpu_time_instrumentation_installed?).to be true
          ran_assertion = true
        end.join

        expect(ran_assertion).to be true
      end

      it 'returns the started thread' do
        new_thread = nil

        returned_thread = thread_class.start do
          new_thread = Thread.current
        end

        returned_thread.join

        expect(returned_thread).to be new_thread
      end

      it 'correctly forwards all received arguments to the passed proc' do
        ran_assertion = false

        thread_class.start(1, 2, 3, four: 4, five: 5) do |*args, **kwargs|
          expect(args).to eq [1, 2, 3]
          expect(kwargs).to eq(four: 4, five: 5)

          ran_assertion = true
        end.join

        expect(ran_assertion).to be true
      end

      it 'sets the return of the user block as the return value of the thread' do
        new_thread = thread_class.start do
          :returned_value
        end

        expect(new_thread.value).to be :returned_value
      end
    end

    describe '#fork' do
      it 'is an alias for start' do
        expect(thread_class.method(:start)).to eq thread_class.method(:fork)
      end
    end
  end
end
