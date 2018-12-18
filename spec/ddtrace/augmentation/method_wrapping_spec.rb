require 'spec_helper'

require 'ddtrace/augmentation/method_wrapping'

RSpec.describe Datadog::MethodWrapping do
  subject(:object) { test_class.new }
  let(:test_class) do
    stub_const('TestClass', Class.new { include Datadog::MethodWrapping })
  end

  describe '#wrapped_methods' do
    subject(:wrapped_methods) { object.wrapped_methods }
    it { is_expected.to be_a_kind_of(Set) }
    it { is_expected.to be_empty }

    context 'after #override_method!' do
      let(:method_name) { :foo }
      before(:each) { object.override_method!(method_name) {} }
      it { is_expected.to include(method_name) }
    end

    context 'after #wrap_method!' do
      let(:method_name) { :to_s }
      before(:each) { object.wrap_method!(method_name) {} }
      it { is_expected.to include(method_name) }
    end
  end

  describe '#override_method!' do
    subject(:override_method!) { object.override_method!(method_name, &block) }
    let(:method_name) { :foo }

    context 'with no block' do
      it { expect { object.override_method!(method_name) }.to_not raise_error }
      it { expect { object.override_method!(method_name) }.to_not(change { object.wrapped_methods }) }
    end

    context 'when provided with a block' do
      let(:args) { [:bar, :baz] }
      let(:block) { proc {} }

      it 'intercepts the wrapped method' do
        expect do |b|
          object.override_method!(method_name, &b)
          object.send(method_name, *args, &block)
        end.to yield_with_args(*args, &block)
      end

      context 'which forwards through the wrapper' do
        let(:test_class) do
          stub_const('TestClass', Class.new do
            include Datadog::MethodWrapping
            def to_s
              'test'
            end
          end)
        end

        it 'invokes the original method correctly' do
          wrapper = spy('wrapper')
          object.override_method!(:to_s) do |*args, &block|
            wrapper.call(*args, &block)
            super()
          end

          expect(object.to_s(*args, &block)).to eq('test')
          expect(wrapper).to have_received(:call)
            .with(*args, &block)
        end
      end
    end
  end

  describe '#wrap_method!' do
    subject(:wrap_method!) { object.wrap_method!(method_name, &block) }
    let(:method_name) { :to_s }
    let(:original_method) { object.method(:to_s) }

    context 'with no block' do
      it { expect { object.wrap_method!(method_name) }.to_not raise_error }
      it { expect { object.wrap_method!(method_name) }.to_not(change { object.wrapped_methods }) }
    end

    context 'when provided with a block' do
      let(:args) { [:bar, :baz] }
      let(:block) { proc {} }

      it 'intercepts the wrapped method' do
        expect do |b|
          object.wrap_method!(method_name, &b)
          object.send(method_name, *args, &block)
        end.to yield_with_args(original_method, *args, &block)
      end

      context 'which forwards through the wrapper' do
        let(:test_class) do
          stub_const('TestClass', Class.new do
            include Datadog::MethodWrapping
            def to_s
              'test'
            end
          end)
        end

        it 'invokes the original method correctly' do
          wrapper = spy('wrapper')
          object.wrap_method!(:to_s) do |original, *args, &block|
            wrapper.call(*args, &block)
            original.call
          end

          expect(object.to_s(*args, &block)).to eq('test')
          expect(wrapper).to have_received(:call)
            .with(*args, &block)
        end
      end
    end
  end
end
