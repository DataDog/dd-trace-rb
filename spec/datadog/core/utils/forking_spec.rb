require 'spec_helper'

require 'datadog/core/utils/forking'

RSpec.describe Datadog::Core::Utils::Forking do
  before do
    skip 'Fork not supported on current platform' unless Process.respond_to?(:fork)
  end

  shared_examples_for 'a Forking type' do
    # Assume the module is defined in the parent process not the fork.
    # (Invoking it "before" prevents lazy definition in the fork.)
    before { test_object }

    describe '#after_fork!' do
      subject(:after_fork!) { test_object.after_fork!(&block) }

      let(:block) { proc {} }

      context 'when the process forks' do
        it 'invokes the block given' do
          expect_in_fork do
            result = nil
            expect { |b| result = test_object.after_fork!(&b) }.to yield_control
            expect(result).to be true
          end
        end

        it 'changes the fork PID' do
          expect_in_fork do
            expect { test_object.after_fork!(&block) }
              .to(change { test_object.fork_pid })
          end
        end
      end

      context 'in the same process' do
        it 'does not invokes the block given' do
          result = nil
          expect { |b| result = test_object.after_fork!(&b) }.to_not yield_control
          expect(result).to be false
        end

        it 'does not change the fork PID' do
          expect { test_object.after_fork!(&block) }
            .to_not(change { test_object.fork_pid })
        end
      end
    end

    describe '#forked?' do
      subject(:forked?) { test_object.forked? }

      context 'when the process forks' do
        it { expect_in_fork { is_expected.to be true } }
      end

      context 'in the same process' do
        it { is_expected.to be false }
      end
    end

    describe '#update_fork_pid!' do
      subject(:update_fork_pid!) { test_object.update_fork_pid! }

      context 'when the process forks' do
        it do
          expect_in_fork do
            expect { test_object.update_fork_pid! }
              .to change { test_object.fork_pid }
              .to(Process.pid)
          end
        end
      end

      context 'in the same process' do
        it do
          # Expect it not to change because the PID should have already
          # been set for this process, thus it should remain the same.
          expect { test_object.update_fork_pid! }
            .to_not(change { test_object.fork_pid })
        end
      end
    end

    describe '#fork_pid' do
      subject(:fork_pid) { test_object.fork_pid }

      context 'when the process forks' do
        it { expect_in_fork { is_expected.to_not eq(Process.pid) } }
      end

      context 'in the same process' do
        it { is_expected.to eq(Process.pid) }
      end
    end
  end

  describe 'when extended by a module' do
    subject(:test_object) { Module.new { extend Datadog::Core::Utils::Forking } }

    it_behaves_like 'a Forking type'
  end

  describe 'when included in a class' do
    subject(:test_object) { test_class.new }

    let(:test_class) { Class.new { include Datadog::Core::Utils::Forking } }

    it_behaves_like 'a Forking type'
  end
end
