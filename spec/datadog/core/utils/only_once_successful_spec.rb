require 'datadog/core/utils/only_once_successful'

RSpec.describe Datadog::Core::Utils::OnlyOnceSuccessful do
  subject(:only_once_successful) { described_class.new(limit) }

  let(:limit) { 0 }

  describe '#run' do
    context 'when limitless' do
      context 'before running once' do
        it do
          expect { |block| only_once_successful.run(&block) }.to yield_control
        end

        it 'returns the result of the block ran' do
          expect(only_once_successful.run { :result }).to be :result
        end
      end

      context 'after running once' do
        let(:result) { nil }

        before do
          only_once_successful.run { result }
        end

        context 'when block returns truthy value' do
          let(:result) { true }

          it do
            expect { |block| only_once_successful.run(&block) }.to_not yield_control
          end

          it do
            expect(only_once_successful.run { :result }).to be nil
          end
        end

        context 'when block returns falsey value' do
          let(:result) { false }

          it do
            expect { |block| only_once_successful.run(&block) }.to yield_control
          end

          it 'runs again until block returns truthy value' do
            expect(only_once_successful.run { :result }).to be :result

            expect(only_once_successful.run { :result }).to be nil
          end
        end
      end
    end

    context 'when limited' do
      let(:limit) { 2 }

      context 'when block returns truthy value' do
        before { only_once_successful.run { true } }

        it do
          expect { |block| only_once_successful.run(&block) }.to_not yield_control
        end

        it do
          expect(only_once_successful.run { :result }).to be nil
        end
      end

      context 'when block returns falsey value "limit" times' do
        before do
          limit.times do
            only_once_successful.run { false }
          end
        end

        it do
          expect { |block| only_once_successful.run(&block) }.to_not yield_control
        end

        it do
          expect(only_once_successful.run { :result }).to be nil
        end
      end
    end

    context 'when run throws an exception' do
      it 'propagates the exception out' do
        exception = RuntimeError.new('boom')

        expect { only_once_successful.run { raise exception } }.to raise_exception(exception)
      end

      it 'runs again' do
        only_once_successful.run { raise 'boom' } rescue nil

        expect { |block| only_once_successful.run(&block) }.to yield_control
      end
    end
  end

  describe '#ran?' do
    context 'before running once' do
      it do
        expect(only_once_successful.ran?).to be false
      end
    end

    context 'after running once' do
      let(:result) { nil }

      before do
        only_once_successful.run { result }
      end

      context 'when block returns truthy value' do
        let(:result) { true }

        it do
          expect(only_once_successful.ran?).to be true
        end
      end

      context 'when block returns falsey value' do
        it do
          expect(only_once_successful.ran?).to be false
        end
      end
    end

    context 'when limited and ran "limit" times' do
      let(:limit) { 2 }

      before do
        limit.times do
          only_once_successful.run { false }
        end
      end

      it do
        expect(only_once_successful.ran?).to be true
      end
    end
  end

  describe '#success?' do
    context 'before running once' do
      it do
        expect(only_once_successful.success?).to be false
      end
    end

    context 'after running once' do
      let(:result) { nil }

      before do
        only_once_successful.run { result }
      end

      context 'when block returns truthy value' do
        let(:result) { true }

        it do
          expect(only_once_successful.success?).to be true
        end
      end

      context 'when block returns falsey value' do
        it do
          expect(only_once_successful.success?).to be false
        end
      end
    end

    context 'when limited and ran "limit" times' do
      let(:limit) { 2 }

      before do
        limit.times do
          only_once_successful.run { false }
        end
      end

      it do
        expect(only_once_successful.success?).to be false
      end
    end
  end

  describe '#failed?' do
    context 'before running once' do
      it do
        expect(only_once_successful.failed?).to be false
      end
    end

    context 'after running once' do
      let(:result) { nil }

      before do
        only_once_successful.run { result }
      end

      context 'when block returns truthy value' do
        let(:result) { true }

        it do
          expect(only_once_successful.failed?).to be false
        end
      end

      context 'when block returns falsey value' do
        it do
          expect(only_once_successful.failed?).to be false
        end
      end
    end

    context 'when limited and ran "limit" times' do
      let(:limit) { 2 }

      before do
        limit.times do
          only_once_successful.run { false }
        end
      end

      it do
        expect(only_once_successful.failed?).to be true
      end
    end
  end
end
