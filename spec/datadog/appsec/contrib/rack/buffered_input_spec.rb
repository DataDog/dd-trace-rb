# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rack/buffered_input'

RSpec.describe Datadog::AppSec::Contrib::Rack::BufferedInput do
  subject(:io) { described_class.new(stream, buffer: buffer) }

  let(:stream) { StringIO.new('world!') }
  let(:buffer) { StringIO.new('hello ') }

  describe '#read' do
    context 'without a length' do
      it { expect(io.read).to eq('hello world!') }
    end

    context 'with a length' do
      it { expect(io.read(3)).to eq('hel') }
      it { expect(io.read(9)).to eq('hello wor') }

      it 'continues across the buffer boundary' do
        expect(io.read(4)).to eq('hell')
        expect(io.read(4)).to eq('o wo')
        expect(io.read(4)).to eq('rld!')
        expect(io.read(4)).to be_nil
      end
    end

    context 'when input is exhausted' do
      before { io.read }

      it { expect(io.read(1)).to be_nil }
      it { expect(io.read).to eq('') }
    end

    context 'when input is exhausted with an output buffer' do
      before { io.read }

      let(:outbuf) { +'stale' }

      it 'clears the output buffer' do
        expect(io.read(1, outbuf)).to be_nil
        expect(outbuf).to eq('')
      end
    end

    context 'when reading into an output buffer' do
      let(:outbuf) { +'stale' }

      it 'returns the output buffer with buffered data' do
        expect(io.read(5, outbuf)).to be(outbuf)
        expect(outbuf).to eq('hello')
      end

      it 'returns the output buffer with all data' do
        expect(io.read(nil, outbuf)).to be(outbuf)
        expect(outbuf).to eq('hello world!')
      end
    end

    context 'when reading into an output buffer after the buffer is drained' do
      before { io.read(6) }

      let(:outbuf) { +'stale' }

      it 'returns the output buffer with stream data' do
        expect(io.read(6, outbuf)).to be(outbuf)
        expect(outbuf).to eq('world!')
      end

      it 'returns the output buffer when reading without a length' do
        expect(io.read(nil, outbuf)).to be(outbuf)
        expect(outbuf).to eq('world!')
      end
    end

    context 'when the stream signals EOF with an empty string' do
      before { allow(stream).to receive(:read).and_wrap_original { |read, *args| read.call(*args) || +'' } }

      let(:stream) { StringIO.new('abc') }
      let(:buffer) { StringIO.new('') }

      it 'treats the empty read as end of input' do
        expect(io.read(3)).to eq('abc')
        expect(io.read(3)).to be_nil
      end
    end
  end

  describe '#gets' do
    context 'with lines split across the buffer boundary' do
      let(:stream) { StringIO.new("ne 2\n") }
      let(:buffer) { StringIO.new("line 1\nli") }

      it { expect(io.gets).to eq("line 1\n") }

      it 'joins the split line' do
        expect(io.gets).to eq("line 1\n")
        expect(io.gets).to eq("line 2\n")
        expect(io.gets).to be_nil
      end
    end

    context 'when the trailing line has no terminator' do
      let(:stream) { StringIO.new('ne 2') }
      let(:buffer) { StringIO.new('li') }

      it { expect(io.gets).to eq('line 2') }
    end
  end

  describe '#each' do
    context 'with buffered and streamed input' do
      it 'yields the full body' do
        expect { |b| io.each(&b) }.to yield_with_args('hello world!')
      end

      it 'returns self' do
        expect(io.each { |_| }).to be(io)
      end
    end

    context 'when the stream signals EOF with an empty string' do
      before { allow(stream).to receive(:read).and_wrap_original { |read, *args| read.call(*args) || +'' } }

      let(:stream) { StringIO.new('abc') }
      let(:buffer) { StringIO.new('') }

      it 'terminates without yielding an empty chunk' do
        expect { |b| io.each(&b) }.to yield_with_args('abc')
      end
    end
  end

  describe '#close' do
    context 'when closing succeeds' do
      it 'closes both wrapped streams' do
        io.close

        expect(buffer).to be_closed
        expect(stream).to be_closed
      end
    end

    context 'when closing the buffer raises' do
      before { allow(buffer).to receive(:close).and_raise(IOError, 'buffer close failed') }

      it 'still closes the stream' do
        expect { io.close }.to raise_error(IOError, 'buffer close failed')
        expect(stream).to be_closed
      end
    end
  end
end
