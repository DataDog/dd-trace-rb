# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rack/gateway/request'
require 'rack'

RSpec.describe Datadog::AppSec::Contrib::Rack::Gateway::Request do
  let(:request) do
    described_class.new(
      Rack::MockRequest.env_for(
        'http://example.com:8080/?a=foo&a=bar&b=baz',
        {
          'REQUEST_METHOD' => 'GET', 'REMOTE_ADDR' => '10.10.10.10', 'CONTENT_TYPE' => 'text/html',
          'HTTP_COOKIE' => 'foo=bar', 'HTTP_USER_AGENT' => 'WebKit'
        }
      )
    )
  end

  describe '#query' do
    context 'when query string parsing succeeds' do
      it 'returns URL query information' do
        expect(request.query).to eq({'a' => ['foo', 'bar'], 'b' => 'baz'})
      end
    end

    context 'when query string parsing failed' do
      before { allow(::Rack::Utils).to receive(:parse_query).and_raise RangeError, 'too big' }

      it 'returns empty query' do
        expect(Datadog::AppSec.telemetry).to receive(:report)
          .with(instance_of(RangeError), description: 'AppSec: Failed to parse request query string')

        expect(request.query).to eq({})
      end
    end
  end

  describe '#headers' do
    it 'returns the header information. Strip the HTTP_ prefix and append content-type and content-length information' do
      expected_headers = {
        'content-type' => 'text/html',
        'cookie' => 'foo=bar',
        'user-agent' => 'WebKit',
        'content-length' => '0'
      }
      expect(request.headers).to eq(expected_headers)
    end

    context 'with malformed headers' do
      let(:request) do
        described_class.new(
          Rack::MockRequest.env_for(
            'http://example.com:8080/?a=foo&a=bar&b=baz',
            {
              'REQUEST_METHOD' => 'GET', 'REMOTE_ADDR' => '10.10.10.10', 'CONTENT_TYPE' => 'text/html',
              'HTTP_COOKIE' => 'foo=bar', 'HTTP_USER_AGENT' => 'WebKit',
              'HTTP_' => 'empty header', 'HTTP_123' => 'numbered header',
              'HTTP_123_FOO' => 'alphanumerical header', 'HTTP_FOO_123' => 'reverse alphanumerical header'
            }
          )
        )
      end

      it 'returns the header information. Strip the HTTP_ prefix and append content-type and content-length information' do
        expected_headers = {
          'content-type' => 'text/html',
          'cookie' => 'foo=bar',
          'user-agent' => 'WebKit',
          'content-length' => '0',
          '' => 'empty header',
          '123' => 'numbered header',
          '123-foo' => 'alphanumerical header',
          'foo-123' => 'reverse alphanumerical header'
        }
        expect(request.headers).to eq(expected_headers)
      end
    end
  end

  describe '#url' do
    it 'returns the url' do
      expect(request.url).to eq('http://example.com:8080/?a=foo&a=bar&b=baz')
    end
  end

  describe '#path' do
    it 'returns the path' do
      expect(request.path).to eq('/')
    end
  end

  describe '#fullpath' do
    it 'returns the path with query string' do
      expect(request.fullpath).to eq('/?a=foo&a=bar&b=baz')
    end
  end

  describe '#host' do
    it 'returns the host' do
      expect(request.host).to eq('example.com')
    end
  end

  describe '#cookies' do
    it 'returns the cookie information' do
      expect(request.cookies).to eq({'foo' => 'bar'})
    end
  end

  describe '#user_agent' do
    it 'returns the user agnet information' do
      expect(request.user_agent).to eq('WebKit')
    end
  end

  describe '#remote_addr' do
    it 'returns the remote address information' do
      expect(request.remote_addr).to eq('10.10.10.10')
    end
  end

  describe '#client_ip' do
    it 'returns the client_ip' do
      expect(request.client_ip).to eq('10.10.10.10')
    end
  end

  describe '#method' do
    it 'returns the request method' do
      expect(request.method).to eq('GET')
    end
  end

  describe '#form_hash' do
    context 'GET request' do
      it 'returns nil' do
        expect(request.form_hash).to be_nil
      end
    end

    context 'POST request' do
      let(:request) do
        described_class.new(
          Rack::MockRequest.env_for(
            'http://example.com:8080/?a=foo',
            {:method => 'POST', :input => 'name=john', 'REMOTE_ADDR' => '10.10.10.10'}
          )
        )
      end

      it 'returns information' do
        expect(request.form_hash).to eq({'name' => 'john'})
      end
    end
  end

  describe '#body_bytesize' do
    let(:request) do
      described_class.new(
        Rack::MockRequest.env_for(
          'http://example.com:8080/',
          {
            :method => 'POST',
            :input => 'name=john',
            'CONTENT_TYPE' => 'application/x-www-form-urlencoded'
          }
        )
      )
    end

    context 'when the body stream reports its size' do
      it 'returns the size and leaves the body readable' do
        expect(request.body_bytesize(100)).to eq(9)
        expect(request.request.body.read).to eq('name=john')
      end
    end

    context 'when there is no request body' do
      before { request.env['rack.input'] = nil }

      it { expect(request.body_bytesize(100)).to eq(0) }
    end

    context 'when the size is unknown but Content-Length is set' do
      before do
        request.env['CONTENT_LENGTH'] = '42'
        request.env['rack.input'] = sizeless_io
      end

      let(:sizeless_io) do
        StringIO.new('name=john').tap do |io|
          allow(io).to receive(:respond_to?).and_call_original
          allow(io).to receive(:respond_to?).with(:size).and_return(false)
        end
      end

      it 'returns the Content-Length without reading the body' do
        expect(request.body_bytesize(100)).to eq(42)
        expect(request.env['rack.input']).to be(sizeless_io)
      end
    end

    context 'when the size is unknown and there is no Content-Length' do
      before do
        request.env.delete('CONTENT_LENGTH')
        request.env['rack.input'] = body_io
      end

      let(:body_io) do
        StringIO.new('name=john').tap do |io|
          allow(io).to receive(:respond_to?).and_call_original
          allow(io).to receive(:respond_to?).with(:size).and_return(false)
        end
      end

      context 'when Rack 3 or later is used' do
        before { skip 'Rack 3 or later behavior' if Gem::Version.new(::Rack.release) < Gem::Version.new('3') }

        context 'when the body fits within the limit' do
          it 'buffers the whole body and keeps it readable' do
            expect(request.body_bytesize(100)).to eq(9)
            expect(request.env['rack.input']).to be_a(StringIO)
            expect(request.env['rack.input'].read).to eq('name=john')
          end
        end

        context 'when the body was already parsed upstream' do
          before do
            request.env['rack.request.form_hash'] = {'name' => 'john'}
            body_io.read
          end

          it { expect(request.body_bytesize(100)).to be_nil }
        end

        context 'when the body exceeds the limit' do
          it 'wraps the body in a forward-only input and returns nil' do
            expect(request.body_bytesize(4)).to be_nil
            expect(request.env['rack.input']).to be_a(Datadog::AppSec::Contrib::Rack::BufferedInput)
            expect(request.env['rack.input'].read).to eq('name=john')
          end
        end

        context 'when the body size is exactly the limit' do
          it 'treats it as within the limit and returns the size' do
            expect(request.body_bytesize(9)).to eq(9)
            expect(request.env['rack.input']).to be_a(StringIO)
            expect(request.env['rack.input'].read).to eq('name=john')
          end
        end

        context 'when the body size is one byte over the limit' do
          it 'treats it as over the limit and returns nil' do
            expect(request.body_bytesize(8)).to be_nil
            expect(request.env['rack.input']).to be_a(Datadog::AppSec::Contrib::Rack::BufferedInput)
            expect(request.env['rack.input'].read).to eq('name=john')
          end
        end

        context 'when the input exposes rewind' do
          before { allow(body_io).to receive(:rewind) }

          it 'does not rely on rewind to restore the body' do
            request.body_bytesize(4)

            expect(body_io).not_to have_received(:rewind)
          end
        end
      end

      context 'when Rack 2 or earlier is used' do
        before { skip 'Rack 2 or earlier behavior' if Gem::Version.new(::Rack.release) >= Gem::Version.new('3') }

        context 'when the body fits within the limit' do
          it 'rewinds the input in place and returns the size' do
            expect(request.body_bytesize(100)).to eq(9)
            expect(request.env['rack.input']).to be(body_io)
            expect(request.env['rack.input'].read).to eq('name=john')
          end
        end

        context 'when the body exceeds the limit' do
          it 'rewinds the input in place and returns nil' do
            expect(request.body_bytesize(4)).to be_nil
            expect(request.env['rack.input']).to be(body_io)
            expect(request.env['rack.input'].read).to eq('name=john')
          end
        end
      end

      context 'when the streaming input returns short reads' do
        let(:body_io) do
          StringIO.new('name=john').tap do |io|
            allow(io).to receive(:respond_to?).and_call_original
            allow(io).to receive(:respond_to?).with(:size).and_return(false)
            allow(io).to receive(:respond_to?).with(:rewind).and_return(false)

            read = io.method(:read)
            allow(io).to receive(:read) { |length, *rest| read.call(length && [length, 5].min, *rest) }
          end
        end

        it 'reads the whole body across reads and returns the full size' do
          expect(request.body_bytesize(100)).to eq(9)
          expect(request.env['rack.input'].read).to eq('name=john')
        end
      end
    end
  end

  describe '#collectable_body?' do
    context 'when the request carries form data' do
      let(:request) do
        described_class.new(
          Rack::MockRequest.env_for(
            'http://example.com:8080/',
            {:method => 'POST', :input => 'name=john', 'CONTENT_TYPE' => 'application/x-www-form-urlencoded'}
          )
        )
      end

      it { expect(request.collectable_body?).to be(true) }
    end

    context 'when the body was already parsed upstream' do
      let(:request) do
        described_class.new(
          Rack::MockRequest.env_for(
            'http://example.com:8080/',
            {:method => 'POST', 'CONTENT_TYPE' => 'application/json', 'rack.request.form_hash' => {'name' => 'john'}}
          )
        )
      end

      it { expect(request.collectable_body?).to be(true) }
    end

    context 'when the request has no collectable body' do
      let(:request) do
        described_class.new(
          Rack::MockRequest.env_for(
            'http://example.com:8080/',
            {:method => 'POST', :input => '{"name":"john"}', 'CONTENT_TYPE' => 'application/json'}
          )
        )
      end

      it { expect(request.collectable_body?).to be(false) }
    end
  end
end
