require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Patchable do
  describe 'implemented' do
    subject(:patchable_class) do
      Class.new.tap do |klass|
        klass.send(:include, described_class)
      end
    end

    describe 'class behavior' do
      describe '#compatible?' do
        subject(:compatible) { patchable_class.compatible? }
        let(:expected_compatibility) { RUBY_VERSION >= '1.9.3' ? true : false }
        it { is_expected.to be expected_compatibility }
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
          context 'is compatible' do
            before(:each) { allow(patchable_class).to receive(:compatible?).and_return(true) }

            context 'and the patcher is defined' do
              let(:patcher) { double('patcher') }
              before(:each) { allow(patchable_object).to receive(:patcher).and_return(patcher) }

              it 'applies the patch' do
                expect(patcher).to receive(:patch)
                patch
              end
            end

            context 'and the patcher is nil' do
              it 'does not applies the patch' do
                is_expected.to be nil
              end
            end
          end

          context 'is not compatible' do
            it 'does not applies the patch' do
              is_expected.to be nil
            end
          end
        end
      end
    end
  end
end
