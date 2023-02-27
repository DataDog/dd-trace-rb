require 'datadog/core/utils/only_once'

RSpec.describe Datadog::Core::Utils::OnlyOnce do
  subject(:only_once) { described_class.new }

  describe '#run' do
    context 'before running once' do
      it do
        expect { |block| only_once.run(&block) }.to yield_control
      end

      it 'returns the result of the block ran' do
        expect(only_once.run { :result }).to be :result
      end
    end

    context 'after running once' do
      before do
        only_once.run {}
      end

      it do
        expect { |block| only_once.run(&block) }.to_not yield_control
      end

      it do
        expect(only_once.run { :result }).to be nil
      end
    end

    context 'when run throws an exception' do
      it 'propagates the exception out' do
        exception = RuntimeError.new('boom')

        expect { only_once.run { raise exception } }.to raise_exception(exception)
      end

      it 'does not run again' do
        only_once.run { raise 'boom' } rescue nil

        expect { |block| only_once.run(&block) }.to_not yield_control
      end
    end
  end

  describe '#ran?' do
    context 'before running once' do
      it do
        expect(only_once.ran?).to be false
      end
    end

    context 'after running once' do
      before do
        only_once.run {}
      end

      it do
        expect(only_once.ran?).to be true
      end
    end
  end
end
