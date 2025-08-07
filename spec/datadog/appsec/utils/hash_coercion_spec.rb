# frozen_string_literal: true

require 'datadog/appsec/utils/hash_coercion'

RSpec.describe Datadog::AppSec::Utils::HashCoercion do
  describe '.coerce' do
    context 'when object responds to as_json' do
      let(:obj) do
        Class.new do
          def as_json; {foo: 'bar'}; end
        end
      end
      it { expect(described_class.coerce(obj.new)).to eq({foo: 'bar'}) }
    end

    context 'when object responds to to_hash' do
      let(:obj) do
        Class.new do
          def to_hash; {bar: 'baz'}; end
        end
      end
      it { expect(described_class.coerce(obj.new)).to eq({bar: 'baz'}) }
    end

    context 'when object responds to to_h' do
      let(:obj) do
        Class.new do
          def to_h; {baz: 'qux'}; end
        end
      end
      it { expect(described_class.coerce(obj.new)).to eq({baz: 'qux'}) }
    end

    context 'when object does not respond to any hash conversion' do
      it { expect(described_class.coerce(Object.new)).to be_nil }
    end
  end
end
