require 'spec_helper'

require 'ddtrace/augmentation/method_wrapper'

RSpec.describe Datadog::MethodWrapper do
  subject(:wrapper) { described_class.new(original_method, &block) }
  let(:original_method) { spy('original method') }

  describe '#call' do
    subject(:call) { wrapper.call(*call_args, &call_block) }
    let(:call_args) { [:bar, :baz] }
    let(:call_block) { proc {} }

    context 'after initialized without a block' do
      let(:block) { nil }

      it 'invokes the original method correctly' do
        call
        expect(original_method).to have_received(:call)
          .with(*call_args, &call_block)
      end
    end

    context 'after initialized with a block' do
      let(:interceptor) { spy('interceptor') }
      let(:block) do
        proc do |original, *args, &block|
          interceptor.call(*args, &block)
          original.call(*args, &block)
        end
      end

      it 'invokes the original method correctly' do
        call

        expect(interceptor).to have_received(:call)
          .with(*call_args, &call_block)

        expect(original_method).to have_received(:call)
          .with(*call_args, &call_block)
      end
    end
  end
end
