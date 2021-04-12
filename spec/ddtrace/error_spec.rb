RSpec.describe Datadog::Error do
  context 'with default values' do
    let(:error) { described_class.new }

    it do
      expect(error.type).to be_empty
      expect(error.message).to be_empty
      expect(error.backtrace).to be_empty
    end

    # Empty strings were being interpreted as ASCII strings breaking `msgpack`
    # decoding on the agent-side.
    it 'encodes default values in UTF-8' do
      error = described_class.new

      expect(error.type.encoding).to eq(::Encoding::UTF_8)
      expect(error.message.encoding).to eq(::Encoding::UTF_8)
      expect(error.backtrace.encoding).to eq(::Encoding::UTF_8)
    end
  end

  context 'with all values provided' do
    let(:error) { described_class.new('ErrorClass', 'message', %w[line1 line2 line3]) }

    it do
      expect(error.type).to eq('ErrorClass')
      expect(error.message).to eq('message')
      expect(error.backtrace).to eq("line1\nline2\nline3")
    end
  end

  describe '.build_from' do
    subject(:error) { described_class.build_from(value) }

    context 'with an exception' do
      let(:value) { ZeroDivisionError.new('divided by 0') }

      it do
        expect(error.type).to eq('ZeroDivisionError')
        expect(error.message).to eq('divided by 0')
        expect(error.backtrace).to be_empty
      end
    end

    context 'with an array' do
      let(:value) { ['ZeroDivisionError', 'divided by 0'] }

      it do
        expect(error.type).to eq('ZeroDivisionError')
        expect(error.message).to eq('divided by 0')
        expect(error.backtrace).to be_empty
      end
    end

    context 'with a custom object responding to :message' do
      let(:value) do
        # RSpec 'double' hijacks the #class method, thus not allowing us
        # to organically test the `Error#type` inferred for this object.
        clazz = stub_const('Test::CustomMessage', Struct.new(:message))
        clazz.new('custom msg')
      end

      it do
        expect(error.type).to eq('Test::CustomMessage')
        expect(error.message).to eq('custom msg')
        expect(error.backtrace).to be_empty
      end
    end

    context 'with nil' do
      let(:value) { nil }

      it do
        expect(error.type).to be_empty
        expect(error.message).to be_empty
        expect(error.backtrace).to be_empty
      end
    end

    context 'with a utf8 incompatible message' do
      let(:value) { StandardError.new("\xC2".force_encoding(::Encoding::ASCII_8BIT)) }

      it 'discards unencodable value' do
        expect(error.type).to eq('StandardError')
        expect(error.message).to be_empty
        expect(error.backtrace).to be_empty
      end
    end
  end
end
