require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Patchable do
  include_context 'tracer logging'

  describe 'implemented' do
    subject(:patchable_class) do
      Class.new.tap do |klass|
        klass.send(:include, described_class)
      end
    end

    describe 'class behavior' do
      describe '#version' do
        subject(:compatible) { patchable_class.version }
        it { is_expected.to be nil }
      end

      describe '#available?' do
        subject(:available?) { patchable_class.available? }

        context 'when version' do
          context 'is defined' do
            let(:version) { double('version') }
            before { allow(patchable_class).to receive(:version).and_return(version) }
            it { is_expected.to be true }
          end

          context 'is not defined' do
            it { is_expected.to be false }
          end
        end
      end

      describe '#loaded?' do
        subject(:loaded?) { patchable_class.loaded? }
        it { is_expected.to be true }
      end

      describe '#compatible?' do
        subject(:compatible?) { patchable_class.compatible? }

        context 'when #available?' do
          context 'is false' do
            before { allow(patchable_class).to receive(:available?).and_return(false) }
            it { is_expected.to be false }
          end

          context 'is true' do
            before { allow(patchable_class).to receive(:available?).and_return(true) }

            context 'and the Ruby version' do
              context 'is below the minimum' do
                before { stub_const('RUBY_VERSION', '1.9.3') }
                it { is_expected.to be false }
              end

              context 'is meets the minimum' do
                it { is_expected.to be true }
              end
            end
          end
        end
      end

      describe '#patchable?' do
        subject(:patchable?) { patchable_class.patchable? }

        context 'default' do
          it { is_expected.to be false }
        end

        context 'when version is defined' do
          let(:version) { double('version') }
          before { allow(patchable_class).to receive(:version).and_return(version) }
          it { is_expected.to be true }
        end

        [
          { available?: true, loaded?: true, compatible?: true, expect: true },
          { available?: false, loaded?: true, compatible?: true, expect: false },
          { available?: true, loaded?: false, compatible?: true, expect: false },
          { available?: true, loaded?: true, compatible?: false, expect: false }
        ].each do |test_case|
          # rubocop:disable Metrics/LineLength
          context "when available? (#{test_case[:available?]}) loaded? (#{test_case[:loaded?]}) compatible? (#{test_case[:compatible?]})" do
            before do
              allow(patchable_class). to receive(:available?).and_return(test_case[:available?])
              allow(patchable_class). to receive(:loaded?).and_return(test_case[:loaded?])
              allow(patchable_class). to receive(:compatible?).and_return(test_case[:compatible?])
            end

            it { is_expected.to be test_case[:expect] }
          end
        end
      end
    end

    describe 'instance behavior' do
      subject(:patchable_object) { patchable_class.new }

      describe '#patcher' do
        subject(:patcher) { patchable_object.patcher }
        it { is_expected.to be nil }
      end

      describe '#patch' do
        subject(:patch) { patchable_object.patch }

        context 'when the patchable object' do
          let(:unpatched_warnings) do
            [
              /.*Unable to patch*/
            ]
          end

          context 'is patchable' do
            before { allow(patchable_class).to receive(:patchable?).and_return(true) }

            context 'and the patcher is defined' do
              let(:patcher) { double('patcher') }
              before { allow(patchable_object).to receive(:patcher).and_return(patcher) }

              it 'applies the patch' do
                expect(patcher).to receive(:patch)
                patch
              end
            end

            context 'and the patcher is nil' do
              it 'does not applies the patch' do
                is_expected.to be nil
                expect(log_buffer).to contain_line_with(*unpatched_warnings)
              end
            end
          end

          context 'is not compatible' do
            it 'does not applies the patch' do
              is_expected.to be nil
              expect(log_buffer).to contain_line_with(*unpatched_warnings)
            end
          end
        end
      end
    end
  end
end
