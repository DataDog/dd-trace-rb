# encoding: utf-8

require 'spec_helper'
require 'ddtrace/runtime/object_space'

RSpec.describe Datadog::Runtime::ObjectSpace do
  describe '::estimate_bytesize' do
    subject(:estimate_bytesize) { described_class.estimate_bytesize(object) }

    context 'given an Object' do
      let(:object) { Object.new }
      let(:expected_size) { ::ObjectSpace.respond_to?(:memsize_of) ? ::ObjectSpace.memsize_of(object) : 0 }

      it { is_expected.to be_a_kind_of(Integer) }
      it { is_expected.to eq expected_size }

      context 'with instance variables' do
        before { skip('ObjectSpace#memsize_of not supported.') unless ::ObjectSpace.respond_to?(:memsize_of) }

        let(:object) { object_class.new(a, b, c) }
        let(:object_class) do
          stub_const('TestClass', Class.new do
            def initialize(a, b, c)
              @a = a
              @b = b
              @c = c
            end
          end)
        end

        let(:a) { [] }
        let(:b) { (0..1000).map { 'a' }.join }
        let(:c) { 123.456 }

        it 'is the size of the object and its instance variables' do
          is_expected.to eq(
            ::ObjectSpace.memsize_of(object) \
            + ::ObjectSpace.memsize_of(a) \
            + ::ObjectSpace.memsize_of(b) \
            + ::ObjectSpace.memsize_of(c)
          )
        end
      end
    end
  end
end
