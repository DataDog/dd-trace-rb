require 'datadog/appsec/spec_helper'
require 'datadog/appsec/finalizable_ref'

RSpec.describe Datadog::AppSec::FinalizableRef do
  subject(:finalizable_ref) { described_class.new(initial_obj, finalizer: :finalize_me!) }

  let(:test_object_class) do
    Class.new do
      def initialize
        @finalized = false
      end

      def finalize_me!
        @finalized = true
      end

      def finalized?
        @finalized
      end
    end
  end

  let(:initial_obj) { test_object_class.new }

  describe '#acquire' do
    it 'returns the current object' do
      expect(finalizable_ref.acquire).to eq(initial_obj)
    end
  end

  describe '#release' do
    it 'does not finalize current object when releasing' do
      obj = finalizable_ref.acquire
      finalizable_ref.release(obj)

      expect(initial_obj.finalized?).to be false
    end

    it 'finalizes outdated objects when their count reaches zero' do
      obj1 = finalizable_ref.acquire

      finalizable_ref.current = test_object_class.new
      finalizable_ref.release(obj1)

      expect(initial_obj.finalized?).to be true
    end

    it 'does not finalize outdated objects while they still have references' do
      obj1 = finalizable_ref.acquire
      obj2 = finalizable_ref.acquire

      finalizable_ref.current = test_object_class.new

      finalizable_ref.release(obj1)
      expect(initial_obj.finalized?).to be false

      finalizable_ref.release(obj2)
      expect(initial_obj.finalized?).to be true
    end

    it 'handles finalization errors gracefully' do
      class_with_failing_finalize = Class.new do
        def finalize!
          raise StandardError, 'Some error message'
        end
      end

      ref = described_class.new(class_with_failing_finalize.new)

      obj = ref.acquire
      ref.current = test_object_class.new

      expect(Datadog.logger).to receive(:debug).with(/Couldn't finalize/)
      expect { ref.release(obj) }.not_to raise_error
    end
  end

  describe '#current=' do
    it 'changes the current object' do
      new_obj = test_object_class.new
      finalizable_ref.current = new_obj

      expect(finalizable_ref.acquire).to eq(new_obj)
    end
  end
end
