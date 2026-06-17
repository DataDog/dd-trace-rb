# frozen_string_literal: true

require 'rack'
require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rack/input_peeker'

RSpec.describe Datadog::AppSec::Contrib::Rack::InputPeeker do
  describe '.peek_bytesize' do
    subject(:bytesize) { described_class.peek_bytesize(env, limit: 100) }

    let(:env) { {'rack.input' => rack_input} }
    let(:rack_input) { StringIO.new('name=john') }

    context 'when rack.input is missing' do
      subject(:bytesize) { described_class.peek_bytesize({}, limit: 100) }

      it { expect(bytesize).to be_nil }
    end

    context 'when the body fits within the limit' do
      it 'returns the body bytesize and keeps the body readable' do
        expect(bytesize).to eq(9)
        expect(env['rack.input'].read).to eq('name=john')
      end
    end

    context 'when the body size is exactly the limit' do
      subject(:bytesize) { described_class.peek_bytesize(env, limit: 9) }

      it 'returns the body bytesize and keeps the body readable' do
        expect(bytesize).to eq(9)
        expect(env['rack.input'].read).to eq('name=john')
      end
    end

    context 'when the body is one byte over the limit' do
      subject(:bytesize) { described_class.peek_bytesize(env, limit: 8) }

      it 'returns nil and keeps the body readable' do
        expect(bytesize).to be_nil
        expect(env['rack.input'].read).to eq('name=john')
      end
    end

    context 'when the input returns short reads' do
      let(:rack_input) do
        klass = Class.new do
          def initialize(data)
            @io = StringIO.new(data)
          end

          def read(length = nil, outbuf = nil)
            length = [length, 5].min if length
            @io.read(length, outbuf)
          end

          def rewind
            @io.rewind
          end
        end

        klass.new('name=john')
      end

      it 'returns the full body bytesize and keeps the body readable' do
        expect(bytesize).to eq(9)
        expect(env['rack.input'].read).to eq('name=john')
      end
    end

    if Gem::Version.new(::Rack.release) >= Gem::Version.new('3')
      context 'when Rack 3 input fits within the limit' do
        it 'replaces rack.input with a replay of the full body' do
          expect(bytesize).to eq(9)
          expect(env['rack.input']).to be_a(StringIO)
          expect(env['rack.input'].read).to eq('name=john')
        end
      end

      context 'when Rack 3 input exceeds the limit' do
        subject(:bytesize) { described_class.peek_bytesize(env, limit: 4) }

        it 'replaces rack.input with a buffered replay over the original stream' do
          expect(bytesize).to be_nil
          expect(env['rack.input']).to be_a(Datadog::AppSec::Contrib::Rack::BufferedInput)
          expect(env['rack.input'].read).to eq('name=john')
        end
      end

      context 'when Rack 3 input responds to rewind' do
        before { allow(rack_input).to receive(:rewind) }

        it 'does not rely on rewind to restore downstream reads' do
          bytesize

          expect(rack_input).not_to have_received(:rewind)
        end
      end
    end

    if Gem::Version.new(::Rack.release) < Gem::Version.new('3')
      context 'when Rack 2 input was already consumed' do
        before { rack_input.read }

        it 'rewinds before peeking and after peeking' do
          expect(bytesize).to eq(9)
          expect(env['rack.input']).to be(rack_input)
          expect(env['rack.input'].read).to eq('name=john')
        end
      end

      context 'when Rack 2 input rewind fails' do
        before { allow(Datadog).to receive(:logger).and_return(logger) }

        let(:logger) { instance_double(Datadog::Core::Logger, debug: nil) }

        let(:rack_input) do
          klass = Class.new do
            def initialize(data)
              @io = StringIO.new(data)
            end

            def read(length = nil, outbuf = nil)
              @io.read(length, outbuf)
            end

            def rewind
              raise IOError, 'cannot rewind'
            end
          end

          klass.new('name=john')
        end

        it 'returns nil and logs the rewind failure' do
          expect(bytesize).to be_nil
          expect(logger).to have_received(:debug)
        end
      end
    end
  end
end
