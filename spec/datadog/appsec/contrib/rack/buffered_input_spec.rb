# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rack/buffered_input'

RSpec.describe Datadog::AppSec::Contrib::Rack::BufferedInput do
  subject(:io) { described_class.new(StringIO.new('world!'), buffer: StringIO.new('hello ')) }

  describe '#read' do
    context 'without a length' do
      it { expect(io.read).to eq('hello world!') }
    end

    context 'with a length within the buffer' do
      it { expect(io.read(3)).to eq('hel') }
    end

    context 'with a length spanning the buffer and the stream' do
      it { expect(io.read(9)).to eq('hello wor') }
    end

    context 'with sequential reads across the boundary' do
      it 'consumes both segments in order' do
        aggregate_failures 'reads continue from the stream after the buffer' do
          expect(io.read(4)).to eq('hell')
          expect(io.read(4)).to eq('o wo')
          expect(io.read(4)).to eq('rld!')
          expect(io.read(4)).to be_nil
        end
      end
    end

    context 'at the end of input' do
      before { io.read }

      it { expect(io.read(1)).to be_nil }
      it { expect(io.read).to eq('') }

      it 'clears the supplied output buffer when returning nil' do
        outbuf = +'stale'

        aggregate_failures 'EOF read with an output buffer mirrors IO#read' do
          expect(io.read(1, outbuf)).to be_nil
          expect(outbuf).to eq('')
        end
      end
    end

    context 'with an output buffer' do
      it 'replaces the buffer contents with the read data' do
        outbuf = +'stale'

        aggregate_failures 'output buffer holds the read bytes and is returned' do
          expect(io.read(5, outbuf)).to be(outbuf)
          expect(outbuf).to eq('hello')
        end
      end

      it 'reuses the same output buffer once the buffer is drained' do
        outbuf = +''

        aggregate_failures 'the stream reads into the caller output buffer' do
          expect(io.read(6, outbuf)).to eq('hello ')
          expect(io.read(6, outbuf)).to be(outbuf)
          expect(outbuf).to eq('world!')
        end
      end
    end

    context 'when the stream signals EOF with an empty string' do
      subject(:io) { described_class.new(stream, buffer: StringIO.new('')) }

      let(:stream) do
        StringIO.new('abc').tap do |io|
          read = io.method(:read)
          allow(io).to receive(:read) { |*args| read.call(*args) || +'' }
        end
      end

      it 'treats the empty read as end of input rather than data' do
        aggregate_failures 'an empty-string EOF does not become an empty read result' do
          expect(io.read(3)).to eq('abc')
          expect(io.read(3)).to be_nil
        end
      end
    end
  end

  describe '#gets' do
    subject(:io) { described_class.new(StringIO.new("ne 2\n"), buffer: StringIO.new("line 1\nli")) }

    it 'returns a whole line contained in the buffer' do
      expect(io.gets).to eq("line 1\n")
    end

    it 'joins a line split across the buffer and the stream' do
      aggregate_failures 'a line straddling the boundary is returned whole' do
        expect(io.gets).to eq("line 1\n")
        expect(io.gets).to eq("line 2\n")
        expect(io.gets).to be_nil
      end
    end

    context 'when the trailing line has no terminator' do
      subject(:io) { described_class.new(StringIO.new('ne 2'), buffer: StringIO.new('li')) }

      it { expect(io.gets).to eq('line 2') }
    end
  end

  describe '#each' do
    it 'yields the full body' do
      expect { |b| io.each(&b) }.to yield_with_args('hello world!')
    end

    it 'returns self' do
      expect(io.each { |_| }).to be(io)
    end

    context 'when the stream signals EOF with an empty string' do
      subject(:io) { described_class.new(stream, buffer: StringIO.new('')) }

      let(:stream) do
        StringIO.new('abc').tap do |io|
          read = io.method(:read)
          allow(io).to receive(:read) { |*args| read.call(*args) || +'' }
        end
      end

      it 'terminates instead of looping on the empty read' do
        expect { |b| io.each(&b) }.to yield_with_args('abc')
      end
    end
  end

  describe '#close' do
    subject(:io) { described_class.new(stream, buffer: buffer) }

    let(:stream) { StringIO.new('world') }
    let(:buffer) { StringIO.new('hello') }

    it 'closes both wrapped streams' do
      io.close

      aggregate_failures 'both sides are closed' do
        expect(buffer).to be_closed
        expect(stream).to be_closed
      end
    end
  end

  describe '#rewind' do
    it { expect(io).not_to respond_to(:rewind) }
  end
end
