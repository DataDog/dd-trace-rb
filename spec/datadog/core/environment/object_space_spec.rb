require 'spec_helper'
require 'datadog/core/environment/object_space'

RSpec.describe Datadog::Core::Environment::ObjectSpace do
  describe '.estimate_bytesize_supported?' do
    subject(:estimate_bytesize_supported?) { described_class.estimate_bytesize_supported? }

    it { is_expected.to eq(!PlatformHelpers.jruby?) }
  end

  describe '.estimate_bytesize', if: ::ObjectSpace.respond_to?(:memsize_of) do
    subject(:estimate_bytesize) { described_class.estimate_bytesize(object) }

    it 'sanity check' do
      expect(::ObjectSpace.memsize_of(Object.new)).to be >= 0
    end

    context 'given an Object' do
      let(:object) { Object.new }
      let(:expected_size) { ::ObjectSpace.memsize_of(object) }

      it { is_expected.to be_a_kind_of(Integer) }
      it { is_expected.to eq expected_size }

      context 'with instance variables', if: ::ObjectSpace.respond_to?(:memsize_of) do
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
