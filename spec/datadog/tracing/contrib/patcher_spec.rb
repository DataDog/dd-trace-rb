require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/patcher'

RSpec.describe Datadog::Tracing::Contrib::Patcher do
  before do
    # DEV Resetting with +.and_call_original+ is currently raising a stack overflow error.
    # DEV This seems like a bug in RSpec that we should investigate further.
    RSpec::Mocks.space.any_instance_proxy_for(Datadog::Tracing::Contrib::Patcher::CommonMethods).unstub(:on_patch_error)
  end

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
            stub_const(
              'TestPatcher',
              Class.new do
                include Datadog::Tracing::Contrib::Patcher
              end
            )
          end

          it { expect(patch).to be nil }
        end

        context 'when patcher defines .patch' do
          context 'and .target_version is not defined' do
            let(:patcher) do
              stub_const(
                'TestPatcher',
                Class.new do
                  include Datadog::Tracing::Contrib::Patcher

                  def self.patch
                    :patched
                  end
                end
              )
            end

            it do
              expect(patch).to be :patched
              expect(health_metrics).to have_received(:instrumentation_patched)
                .with(1, tags: array_including('patcher:TestPatcher'))
            end
          end

          context 'and .target_version is defined' do
            let(:patcher) do
              stub_const(
                'TestPatcher',
                Class.new do
                  include Datadog::Tracing::Contrib::Patcher

                  def self.patch
                    :patched
                  end

                  def self.target_version
                    Gem::Version.new(1.0)
                  end
                end
              )
            end

            it do
              expect(patch).to be :patched
              expect(health_metrics).to have_received(:instrumentation_patched)
                .with(1, tags: array_including('patcher:TestPatcher', 'target_version:1.0'))
            end
          end
        end

        context 'when patcher .patch raises an error' do
          before do
            allow(Datadog.logger).to receive(:error)
          end

          context 'and .target_version is not defined' do
            let(:patcher) do
              stub_const(
                'TestPatcher',
                Class.new do
                  include Datadog::Tracing::Contrib::Patcher

                  def self.patch
                    raise StandardError, 'Patch error!'
                  end
                end
              )
            end

            it 'handles the error' do
              expect { patch }.to_not raise_error
              expect(Datadog.logger).to have_received(:error)
                .with(a_patch_error(patcher.name))
              expect(health_metrics).to have_received(:error_instrumentation_patch)
                .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError'))
            end
          end

          context 'and .target_version is defined' do
            let(:patcher) do
              stub_const(
                'TestPatcher',
                Class.new do
                  include Datadog::Tracing::Contrib::Patcher

                  def self.patch
                    raise StandardError, 'Patch error!'
                  end

                  def self.target_version
                    Gem::Version.new(1.0)
                  end
                end
              )
            end

            it 'handles the error' do
              expect { patch }.to_not raise_error
              expect(Datadog.logger).to have_received(:error)
                .with(a_patch_error(patcher.name))
              expect(health_metrics).to have_received(:error_instrumentation_patch)
                .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError', 'target_version:1.0'))
            end
          end
        end
      end

      describe '#patched?' do
        subject(:patched?) { patcher.patched? }

        context 'when patcher does not define .patch' do
          let(:patcher) do
            stub_const(
              'TestPatcher',
              Class.new do
                include Datadog::Tracing::Contrib::Patcher
              end
            )
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
            stub_const(
              'TestPatcher',
              Class.new do
                include Datadog::Tracing::Contrib::Patcher

                def self.patch
                  :patched
                end
              end
            )
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

      describe '#on_patch_error' do
        include_context 'health metrics'

        subject(:on_patch_error) { patcher.on_patch_error(error) }

        let(:error) { instance_double('error', class: StandardError, message: nil, backtrace: []) }

        before do
          allow(Datadog.logger).to receive(:error)
        end

        context 'and .target_version is not defined' do
          let(:patcher) do
            stub_const('TestPatcher', Class.new { include Datadog::Tracing::Contrib::Patcher })
          end

          it 'handles the error' do
            subject
            expect(Datadog.logger).to have_received(:error)
              .with(a_patch_error(patcher.name))
            expect(health_metrics).to have_received(:error_instrumentation_patch)
              .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError'))
          end
        end

        context 'and .target_version is defined' do
          let(:patcher) do
            stub_const(
              'TestPatcher',
              Class.new do
                include Datadog::Tracing::Contrib::Patcher

                def self.target_version
                  Gem::Version.new(1.0)
                end
              end
            )
          end

          it 'handles the error' do
            subject
            expect(Datadog.logger).to have_received(:error)
              .with(a_patch_error(patcher.name))
            expect(health_metrics).to have_received(:error_instrumentation_patch)
              .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError', 'target_version:1.0'))
          end
        end
      end
    end

    describe 'instance behavior' do
      subject(:patcher) { patcher_class.new }

      let(:patcher_class) do
        stub_const(
          'TestPatcher',
          Class.new do
            include Datadog::Tracing::Contrib::Patcher
          end
        )
      end

      describe '#patch' do
        subject(:patch) { patcher.patch }

        context 'when patcher does not define #patch' do
          it { expect(patch).to be nil }
        end

        context 'when patcher defines #patch' do
          let(:patcher_class) do
            stub_const(
              'TestPatcher',
              Class.new do
                include Datadog::Tracing::Contrib::Patcher

                def patch
                  :patched
                end
              end
            )
          end

          it { expect(patch).to be :patched }
        end
      end

      describe '#on_patch_error' do
        include_context 'health metrics'

        subject(:on_patch_error) { patcher.on_patch_error(error) }

        let(:error) { instance_double('error', class: StandardError, message: nil, backtrace: []) }

        before do
          allow(Datadog.logger).to receive(:error)
        end

        context 'and .target_version is not defined' do
          let(:patcher_class) do
            stub_const('TestPatcher', Class.new { include Datadog::Tracing::Contrib::Patcher })
          end

          it 'handles the error' do
            subject
            expect(Datadog.logger).to have_received(:error)
              .with(a_patch_error(patcher_class.name))
            expect(health_metrics).to have_received(:error_instrumentation_patch)
              .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError'))
          end
        end

        context 'and .target_version is defined' do
          let(:patcher_class) do
            stub_const(
              'TestPatcher',
              Class.new do
                include Datadog::Tracing::Contrib::Patcher

                def target_version
                  Gem::Version.new(1.0)
                end
              end
            )
          end

          it 'handles the error' do
            subject
            expect(Datadog.logger).to have_received(:error)
              .with(a_patch_error(patcher_class.name))
            expect(health_metrics).to have_received(:error_instrumentation_patch)
              .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError', 'target_version:1.0'))
          end
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
            stub_const(
              'TestPatcher',
              Module.new do
                include Datadog::Tracing::Contrib::Patcher
              end
            )
          end

          it { expect(patch).to be nil }
        end

        context 'when patcher defines .patch' do
          context 'and .target_version is not defined' do
            let(:patcher) do
              stub_const(
                'TestPatcher',
                Module.new do
                  include Datadog::Tracing::Contrib::Patcher

                  def self.patch
                    :patched
                  end
                end
              )
            end

            it do
              expect(patch).to be :patched
              expect(health_metrics).to have_received(:instrumentation_patched)
                .with(1, tags: array_including('patcher:TestPatcher'))
            end
          end

          context 'and .target_version is defined' do
            let(:patcher) do
              stub_const(
                'TestPatcher',
                Module.new do
                  include Datadog::Tracing::Contrib::Patcher

                  def self.patch
                    :patched
                  end

                  def self.target_version
                    Gem::Version.new(1.0)
                  end
                end
              )
            end

            it do
              expect(patch).to be :patched
              expect(health_metrics).to have_received(:instrumentation_patched)
                .with(1, tags: array_including('patcher:TestPatcher', 'target_version:1.0'))
            end
          end
        end

        context 'when patcher .patch raises an error' do
          before do
            allow(Datadog.logger).to receive(:error)
          end

          context 'and .target_version is not defined' do
            let(:patcher) do
              stub_const(
                'TestPatcher',
                Module.new do
                  include Datadog::Tracing::Contrib::Patcher

                  def self.patch
                    raise StandardError, 'Patch error!'
                  end
                end
              )
            end

            it 'handles the error' do
              expect { patch }.to_not raise_error
              expect(Datadog.logger).to have_received(:error)
                .with(a_patch_error(patcher.name))
              expect(health_metrics).to have_received(:error_instrumentation_patch)
                .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError'))
            end
          end

          context 'and .target_version is defined' do
            let(:patcher) do
              stub_const(
                'TestPatcher',
                Module.new do
                  include Datadog::Tracing::Contrib::Patcher

                  def self.patch
                    raise StandardError, 'Patch error!'
                  end

                  def self.target_version
                    Gem::Version.new(1.0)
                  end
                end
              )
            end

            it 'handles the error' do
              expect { patch }.to_not raise_error
              expect(Datadog.logger).to have_received(:error)
                .with(a_patch_error(patcher.name))
              expect(health_metrics).to have_received(:error_instrumentation_patch)
                .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError', 'target_version:1.0'))
            end
          end
        end
      end

      describe '#patched?' do
        subject(:patched?) { patcher.patched? }

        context 'when patcher does not define .patch' do
          let(:patcher) do
            stub_const(
              'TestPatcher',
              Module.new do
                include Datadog::Tracing::Contrib::Patcher
              end
            )
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
            stub_const(
              'TestPatcher',
              Module.new do
                include Datadog::Tracing::Contrib::Patcher

                def self.patch
                  :patched
                end
              end
            )
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

      describe '#on_patch_error' do
        include_context 'health metrics'

        subject(:on_patch_error) { patcher.on_patch_error(error) }

        let(:error) { instance_double('error', class: StandardError, message: nil, backtrace: []) }

        before do
          allow(Datadog.logger).to receive(:error)
        end

        context 'and .target_version is not defined' do
          let(:patcher) do
            stub_const('TestPatcher', Module.new { include Datadog::Tracing::Contrib::Patcher })
          end

          it 'handles the error' do
            subject
            expect(Datadog.logger).to have_received(:error)
              .with(a_patch_error(patcher.name))
            expect(health_metrics).to have_received(:error_instrumentation_patch)
              .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError'))
          end
        end

        context 'and .target_version is defined' do
          let(:patcher) do
            stub_const(
              'TestPatcher',
              Module.new do
                include Datadog::Tracing::Contrib::Patcher

                def self.target_version
                  Gem::Version.new(1.0)
                end
              end
            )
          end

          it 'handles the error' do
            subject
            expect(Datadog.logger).to have_received(:error)
              .with(a_patch_error(patcher.name))
            expect(health_metrics).to have_received(:error_instrumentation_patch)
              .with(1, tags: array_including('patcher:TestPatcher', 'error:StandardError', 'target_version:1.0'))
          end
        end
      end
    end
  end
end
