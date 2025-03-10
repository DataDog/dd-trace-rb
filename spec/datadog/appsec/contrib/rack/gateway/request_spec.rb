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
    it 'returns URL query information' do
      expect(request.query).to eq({ 'a' => ['foo', 'bar'], 'b' => ['baz'] })
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
      expect(request.cookies).to eq({ 'foo' => 'bar' })
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
            { method: 'POST', input: 'name=john', 'REMOTE_ADDR' => '10.10.10.10' }
          )
        )
      end

      it 'returns information' do
        expect(request.form_hash).to eq({ 'name' => 'john' })
      end
    end
  end
end
