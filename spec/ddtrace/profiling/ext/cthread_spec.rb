require 'spec_helper'
require 'ddtrace/profiling'

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

    let(:thread_class) do
      expect(::Thread.ancestors).to_not include(described_class)

      klass = ::Thread.dup
      klass.send(:prepend, described_class)
      klass
    end

    # Leave Thread class in a clean state before and after tests
    before do
      stub_const('Thread', thread_class)
    end

    # Kill any spawned threads
    after { thread.kill if instance_variable_defined?(:@thread_started) && @thread_started }

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
          clock_id: kind_of(Integer),
          native_thread_id: kind_of(Integer),
          cpu_time: kind_of(Float)
        )
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
      subject(:clock_id) { thread.clock_id }

      it { is_expected.to be_a_kind_of(Integer) }

      context 'main thread' do
        include_context 'with main thread'

        context 'when forked' do
          it 'returns a new clock ID' do
            on_main_thread do
              # Get main thread clock ID
              original_clock_id = thread_class.current.clock_id

              expect_in_fork do
                # Expect main thread clock ID to change (to match fork's main thread)
                expect(thread_class.current.clock_id).to be_a_kind_of(Integer)
                expect(thread_class.current.clock_id).to_not eq(original_clock_id)
              end
            end
          end
        end
      end
    end

    describe '#cpu_time' do
      subject(:cpu_time) { thread.cpu_time }

      context 'when clock ID' do
        before { allow(thread).to receive(:clock_id).and_return(clock_id) }

        context 'is not available' do
          let(:clock_id) { nil }
          it { is_expected.to be nil }
        end

        context 'is available' do
          let(:clock_id) { double('clock ID') }

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
  end
end
