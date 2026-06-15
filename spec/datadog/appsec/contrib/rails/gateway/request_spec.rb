# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rails/gateway/request'
require 'action_dispatch'

RSpec.describe Datadog::AppSec::Contrib::Rails::Gateway::Request do
  subject(:request) { described_class.new(ActionDispatch::Request.new(env)) }

  let(:env) do
    Rack::MockRequest.env_for(
      'http://example.com:8080/',
      {:method => 'POST', :input => 'name=john', 'CONTENT_TYPE' => 'application/x-www-form-urlencoded'}
    )
  end

  describe '#measure_body' do
    context 'when the parsing size limit is zero' do
      it { expect(request.measure_body(0)).to have_attributes(byte_length: nil, collect_body: false) }
    end

    context 'when raw posted data is present' do
      before { env['RAW_POST_DATA'] = '{"name":"john"}' }

      it 'returns its byte length and allows collection within the limit' do
        expect(request.measure_body(100)).to have_attributes(byte_length: 15, collect_body: true)
      end

      context 'and it exceeds the limit' do
        it { expect(request.measure_body(4)).to have_attributes(byte_length: 15, collect_body: false) }
      end
    end

    context 'when raw form vars are present' do
      before { env['rack.request.form_vars'] = 'name=john' }

      it 'returns their byte length and allows collection within the limit' do
        expect(request.measure_body(100)).to have_attributes(byte_length: 9, collect_body: true)
      end

      context 'and they exceed the limit' do
        it { expect(request.measure_body(4)).to have_attributes(byte_length: 9, collect_body: false) }
      end
    end

    context 'when the body stream reports its size' do
      it 'returns the size and allows collection within the limit' do
        expect(request.measure_body(100)).to have_attributes(byte_length: 9, collect_body: true)
      end

      context 'and it exceeds the limit' do
        it { expect(request.measure_body(4)).to have_attributes(byte_length: 9, collect_body: false) }
      end
    end

    context 'when there is no request body' do
      before { env['rack.input'] = nil }

      it { expect(request.measure_body(100)).to have_attributes(byte_length: 0, collect_body: false) }
    end

    context 'when the size is unknown but Content-Length is set' do
      before do
        env['CONTENT_LENGTH'] = '42'
        env['rack.input'] = sizeless_io
      end

      let(:sizeless_io) do
        StringIO.new('name=john').tap do |io|
          allow(io).to receive(:respond_to?).and_call_original
          allow(io).to receive(:respond_to?).with(:size).and_return(false)
        end
      end

      it 'returns the Content-Length without reading the body' do
        expect(request.measure_body(100)).to have_attributes(byte_length: 42, collect_body: true)
        expect(env['rack.input']).to be(sizeless_io)
      end
    end

    context 'when the size is unknown and there is no Content-Length' do
      before do
        env.delete('CONTENT_LENGTH')
        env['rack.input'] = body_io
      end

      let(:body_io) do
        StringIO.new('name=john').tap do |io|
          allow(io).to receive(:respond_to?).and_call_original
          allow(io).to receive(:respond_to?).with(:size).and_return(false)
        end
      end

      if Gem::Version.new(::Rack.release) >= Gem::Version.new('3')
        context 'and the body fits within the limit' do
          it 'buffers the body and allows collection' do
            measurement = request.measure_body(100)

            expect(measurement).to have_attributes(byte_length: 9, collect_body: true)
            expect(env['rack.input']).to be_a(StringIO)
            expect(env['rack.input'].read).to eq('name=john')
          end
        end

        context 'and the body exceeds the limit' do
          it 'wraps the body in a forward-only input and disallows collection' do
            measurement = request.measure_body(4)

            expect(measurement).to have_attributes(byte_length: nil, collect_body: false)
            expect(env['rack.input']).to be_a(Datadog::AppSec::Contrib::Rack::BufferedInput)
            expect(env['rack.input'].read).to eq('name=john')
          end
        end

        context 'and the body was already parsed by Rails' do
          before { env['action_dispatch.request.request_parameters'] = {'name' => 'john'} }

          it 'allows collection of the parsed body without a byte length' do
            expect(request.measure_body(4)).to have_attributes(byte_length: nil, collect_body: true)
          end
        end
      end

      if Gem::Version.new(::Rack.release) < Gem::Version.new('3')
        context 'and the body fits within the limit' do
          it 'rewinds the input in place and allows collection' do
            measurement = request.measure_body(100)

            expect(measurement).to have_attributes(byte_length: 9, collect_body: true)
            expect(env['rack.input']).to be(body_io)
            expect(env['rack.input'].read).to eq('name=john')
          end
        end

        context 'and the body exceeds the limit' do
          it 'rewinds the input in place and disallows collection' do
            measurement = request.measure_body(4)

            expect(measurement).to have_attributes(byte_length: nil, collect_body: false)
            expect(env['rack.input']).to be(body_io)
            expect(env['rack.input'].read).to eq('name=john')
          end
        end
      end
    end
  end
end
