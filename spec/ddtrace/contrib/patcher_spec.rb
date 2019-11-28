require 'spec_helper'

require 'ddtrace/contrib/patcher'

RSpec.describe Datadog::Contrib::Patcher do
  RSpec::Matchers.define :a_patch_error do |name|
    match { |actual| actual.include?("Failed to apply #{name} patch.") }
  end

  describe 'implemented in a class' do
    describe 'class behavior' do
      describe '#patch' do
        include_context 'health metrics'

        subject(:patch) { patcher.patch }

        context 'when patcher does not define .patch' do
          let(:patcher) do
            stub_const('TestPatcher', Class.new do
              include Datadog::Contrib::Patcher
            end)
          end

          it { expect(patch).to be nil }
        end

        context 'when patcher defines .patch' do
          let(:patcher) do
            stub_const('TestPatcher', Class.new do
              include Datadog::Contrib::Patcher

              def self.patch
                :patched
              end
            end)
          end

          it { expect(patch).to be :patched }
        end

        context 'when patcher .patch raises an error' do
          let(:patcher) do
            stub_const('TestPatcher', Class.new do
              include Datadog::Contrib::Patcher

              def self.patch
                raise StandardError, 'Patch error!'
              end
            end)
          end

          before do
            allow(Datadog::Tracer.log).to receive(:error)
            allow(health_metrics).to receive(:error_instrumentation_patch)
          end

          it 'handles the error' do
            expect { patch }.to_not raise_error
            expect(Datadog::Tracer.log).to have_received(:error)
              .with(a_patch_error(patcher.name))
            expect(health_metrics).to have_received(:error_instrumentation_patch)
              .with(1, tags: ['patcher:TestPatcher', 'error:StandardError'])
          end
        end
      end

      describe '#patched?' do
        subject(:patched?) { patcher.patched? }

        context 'when patcher does not define .patch' do
          let(:patcher) do
            stub_const('TestPatcher', Class.new do
              include Datadog::Contrib::Patcher
            end)
          end

          context 'and patch has not been applied' do
            it { expect(patched?).to be false }
          end

          context 'and patch has been applied' do
            before { patcher.patch }
            it { expect(patched?).to be false }
          end
        end

        context 'when patcher defines .patch' do
          let(:patcher) do
            stub_const('TestPatcher', Class.new do
              include Datadog::Contrib::Patcher

              def self.patch
                :patched
              end
            end)
          end

          context 'and patch has not been applied' do
            it { expect(patched?).to be false }
          end

          context 'and patch has been applied' do
            before { patcher.patch }
            it { expect(patched?).to be true }
          end
        end
      end
    end

    describe 'instance behavior' do
      subject(:patcher) { patcher_class.new }
      let(:patcher_class) do
        stub_const('TestPatcher', Class.new do
          include Datadog::Contrib::Patcher
        end)
      end

      it { is_expected.to be_a_kind_of(Datadog::Patcher) }

      describe '#patch' do
        subject(:patch) { patcher.patch }

        context 'when patcher does not define #patch' do
          it { expect(patch).to be nil }
        end

        context 'when patcher defines #patch' do
          let(:patcher_class) do
            stub_const('TestPatcher', Class.new do
              include Datadog::Contrib::Patcher

              def patch
                :patched
              end
            end)
          end

          it { expect(patch).to be :patched }
        end
      end
    end
  end

  describe 'implemented in a module' do
    describe 'module behavior' do
      describe '#patch' do
        include_context 'health metrics'

        subject(:patch) { patcher.patch }

        context 'when patcher does not define .patch' do
          let(:patcher) do
            stub_const('TestPatcher', Module.new do
              include Datadog::Contrib::Patcher
            end)
          end

          it { expect(patch).to be nil }
        end

        context 'when patcher defines .patch' do
          let(:patcher) do
            stub_const('TestPatcher', Module.new do
              include Datadog::Contrib::Patcher

              def self.patch
                :patched
              end
            end)
          end

          it { expect(patch).to be :patched }
        end

        context 'when patcher .patch raises an error' do
          let(:patcher) do
            stub_const('TestPatcher', Module.new do
              include Datadog::Contrib::Patcher

              def self.patch
                raise StandardError, 'Patch error!'
              end
            end)
          end

          before do
            allow(Datadog::Tracer.log).to receive(:error)
          end

          it 'handles the error' do
            expect { patch }.to_not raise_error
            expect(Datadog::Tracer.log).to have_received(:error)
              .with(a_patch_error(patcher.name))
            expect(health_metrics).to have_received(:error_instrumentation_patch)
              .with(1, tags: ['patcher:TestPatcher', 'error:StandardError'])
          end
        end
      end

      describe '#patched?' do
        subject(:patched?) { patcher.patched? }

        context 'when patcher does not define .patch' do
          let(:patcher) do
            stub_const('TestPatcher', Module.new do
              include Datadog::Contrib::Patcher
            end)
          end

          context 'and patch has not been applied' do
            it { expect(patched?).to be false }
          end

          context 'and patch has been applied' do
            before { patcher.patch }
            it { expect(patched?).to be false }
          end
        end

        context 'when patcher defines .patch' do
          let(:patcher) do
            stub_const('TestPatcher', Module.new do
              include Datadog::Contrib::Patcher

              def self.patch
                :patched
              end
            end)
          end

          context 'and patch has not been applied' do
            it { expect(patched?).to be false }
          end

          context 'and patch has been applied' do
            before { patcher.patch }
            it { expect(patched?).to be true }
          end
        end
      end
    end
  end
end
