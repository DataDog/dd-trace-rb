require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Patcher do
  shared_examples_for 'common patcher behavior' do
    describe '#without_warnings' do
      it { expect { |b| patcher.without_warnings(&b) }.to yield_control }
    end

    describe '#do_once' do
      let(:integration) { double('integration', patch: patch_result) }
      let(:patch_result) { double('patch_result') }

      # Because we might be mutating a global level constant,
      # we have to make sure to reset its state.
      after(:each) { patcher.instance_variable_set(:@done_once, nil) }

      context 'when called without a key' do
        subject(:result) { patcher.do_once { integration.patch } }

        it do
          expect(integration).to receive(:patch).once.and_return(patch_result)
          expect(result).to be(patch_result)
        end

        context 'then called a second time' do
          context 'without a key' do
            subject(:result) do
              patcher.do_once { integration.patch }
              patcher.do_once { integration.patch }
            end

            it do
              expect(integration).to receive(:patch).once.and_return(patch_result)
              expect(result).to be true # Because second block doesn't run
            end
          end

          context 'with a key' do
            subject(:result) do
              patcher.do_once { integration.patch }
              patcher.do_once(key) { integration.patch }
            end

            let(:key) { double('key') }

            it do
              expect(integration).to receive(:patch).twice.and_return(patch_result)
              expect(result).to be(patch_result)
            end
          end
        end
      end

      context 'when called with a key' do
        subject(:result) { patcher.do_once(key) { integration.patch } }

        let(:key) { double('key') }

        it do
          expect(integration).to receive(:patch).once.and_return(patch_result)
          expect(result).to be(patch_result)
        end

        context 'then called a second time' do
          context 'without a key' do
            subject(:result) do
              patcher.do_once(key) { integration.patch }
              patcher.do_once { integration.patch }
            end

            it do
              expect(integration).to receive(:patch).twice.and_return(patch_result)
              expect(result).to be(patch_result)
            end
          end

          context 'with a key' do
            context 'that is the same' do
              subject(:result) do
                patcher.do_once(key) { integration.patch }
                patcher.do_once(key) { integration.patch }
              end

              it do
                expect(integration).to receive(:patch).once.and_return(patch_result)
                expect(result).to be true # Because second block doesn't run
              end
            end

            context 'that is different' do
              subject(:result) do
                patcher.do_once(key) { integration.patch }
                patcher.do_once(key_two) { integration.patch }
              end

              let(:key_two) { double('key_two') }

              it do
                expect(integration).to receive(:patch).twice.and_return(patch_result)
                expect(result).to be(patch_result)
              end
            end
          end
        end
      end
    end

    describe '#done?' do
      context 'when called before do_once' do
        subject(:done) { patcher.done?(key) }
        let(:key) { double('key') }
        it { is_expected.to be false }
      end

      context 'when called after do_once' do
        subject(:done) { patcher.done?(key) }
        let(:key) { double('key') }
        before(:each) { patcher.do_once(key) { 'Perform patch' } }
        it { is_expected.to be true }
      end
    end
  end

  describe 'implemented' do
    subject(:patcher_class) do
      Class.new.tap do |klass|
        klass.send(:include, described_class)
      end
    end

    describe 'class' do
      it_behaves_like 'common patcher behavior' do
        let(:patcher) { patcher_class }
      end
    end

    describe 'instance' do
      subject(:patcher) { patcher_class.new }

      it_behaves_like 'common patcher behavior'
    end
  end

  describe 'module' do
    it_behaves_like 'common patcher behavior' do
      let(:patcher) { described_class }
    end
  end
end
