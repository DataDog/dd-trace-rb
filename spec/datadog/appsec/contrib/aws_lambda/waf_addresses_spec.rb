# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/aws_lambda/waf_addresses'

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::WAFAddresses do
  describe '.from_request' do
    subject(:result) { described_class.from_request(payload) }

    context 'when payload has all standard keys' do
      let(:payload) do
        {
          'method' => 'POST',
          'path' => '/users/123',
          'headers' => {'Host' => 'example.com', 'User-Agent' => 'WebKit', 'Cookie' => 'session=abc'},
          'query' => {'page' => ['1']},
          'path_params' => {'id' => '123'},
          'body' => '{"name":"john"}',
          'base64_encoded' => false,
          'source_ip' => '10.0.0.1',
        }
      end

      it { expect(result['server.request.method']).to eq('POST') }
      it { expect(result['server.request.uri.raw']).to eq('/users/123?page=1') }
      it { expect(result['server.request.headers']).to include('host' => 'example.com') }
      it { expect(result['server.request.headers.no_cookies']).not_to have_key('cookie') }
      it { expect(result['server.request.cookies']).to eq('session' => 'abc') }
      it { expect(result['server.request.query']).to eq('page' => ['1']) }
      it { expect(result['server.request.path_params']).to eq('id' => '123') }
      it { expect(result['http.client_ip']).to eq('10.0.0.1') }
    end

    context 'when payload is API Gateway v2 style' do
      let(:payload) do
        {
          'path' => '/users/123',
          'query' => {'page' => '1', 'sort' => 'asc'},
          'query_string' => 'page=1&sort=asc',
          'headers' => {'host' => 'example.com'},
          'source_ip' => '10.0.0.2',
          'method' => 'GET',
        }
      end

      it { expect(result['server.request.method']).to eq('GET') }
      it { expect(result['server.request.uri.raw']).to eq('/users/123?page=1&sort=asc') }
      it { expect(result['server.request.query']).to eq('page' => '1', 'sort' => 'asc') }
      it { expect(result['http.client_ip']).to eq('10.0.0.2') }
    end

    context 'when payload has query_string but no query' do
      let(:payload) do
        {
          'path' => '/users/123',
          'query_string' => 'page=1&sort=asc',
          'headers' => {'host' => 'example.com'},
          'method' => 'GET',
        }
      end

      it { expect(result['server.request.uri.raw']).to eq('/users/123?page=1&sort=asc') }
      it { expect(result).not_to have_key('server.request.query') }
    end

    context 'when query_string is empty and query hash is present' do
      let(:payload) do
        {
          'path' => '/search',
          'query_string' => '',
          'query' => {'q' => ['ruby']},
          'headers' => {},
        }
      end

      it { expect(result['server.request.uri.raw']).to eq('/search?q=ruby') }
      it { expect(result['server.request.query']).to eq('q' => ['ruby']) }
    end

    context 'when payload has no query data' do
      let(:payload) do
        {
          'path' => '/health',
          'headers' => {},
          'source_ip' => '127.0.0.1',
        }
      end

      it { expect(result['server.request.uri.raw']).to eq('/health') }
      it { expect(result).not_to have_key('server.request.query') }
    end

    context 'when payload has no path' do
      let(:payload) { {'headers' => {}} }

      it { expect(result).not_to have_key('server.request.uri.raw') }
    end

    context 'when payload has no method' do
      let(:payload) { {'headers' => {}} }

      it { expect(result).not_to have_key('server.request.method') }
    end

    context 'when payload has base64-encoded JSON body' do
      let(:payload) do
        {
          'headers' => {'Content-Type' => 'application/json'},
          'body' => 'eyJrZXkiOiJ2YWx1ZSJ9',
          'base64_encoded' => true,
        }
      end

      it { expect(result['server.request.body']).to eq('key' => 'value') }
    end

    context 'when payload has plain JSON body' do
      let(:payload) do
        {
          'headers' => {'Content-Type' => 'application/json'},
          'body' => '{"key":"value"}',
          'base64_encoded' => false,
        }
      end

      it { expect(result['server.request.body']).to eq('key' => 'value') }
    end

    context 'when payload has no body' do
      let(:payload) { {'headers' => {}} }

      it { expect(result).not_to have_key('server.request.body') }
    end

    context 'when payload has body with no content-type' do
      let(:payload) do
        {
          'headers' => {},
          'body' => 'some data',
        }
      end

      it { expect(result).not_to have_key('server.request.body') }
    end

    context 'when payload has no path params' do
      let(:payload) { {'headers' => {}} }

      it { expect(result).not_to have_key('server.request.path_params') }
    end

    context 'when cookies come from Cookie header' do
      let(:payload) do
        {
          'headers' => {'Cookie' => 'a=1; b=2; c=val=ue'},
        }
      end

      it { expect(result['server.request.cookies']).to eq('a' => '1', 'b' => '2', 'c' => 'val=ue') }
    end

    context 'when cookies come from cookies array' do
      let(:payload) do
        {
          'headers' => {},
          'cookies' => ['session=abc', 'theme=dark'],
        }
      end

      it { expect(result['server.request.cookies']).to eq('session' => 'abc', 'theme' => 'dark') }
    end

    context 'when cookies array takes precedence over Cookie header' do
      let(:payload) do
        {
          'headers' => {'Cookie' => 'old=stale'},
          'cookies' => ['new=fresh'],
        }
      end

      it { expect(result['server.request.cookies']).to eq('new' => 'fresh') }
    end

    context 'when payload has no cookies' do
      let(:payload) { {'headers' => {}} }

      it { expect(result).not_to have_key('server.request.cookies') }
    end

    context 'when payload has explicit nil fields' do
      let(:payload) do
        {
          'path' => '/health',
          'headers' => nil,
          'query' => nil,
          'path_params' => nil,
          'source_ip' => '127.0.0.1',
        }
      end

      it { expect(result['server.request.headers']).to eq({}) }
      it { expect(result['server.request.headers.no_cookies']).to eq({}) }
      it { expect(result).not_to have_key('server.request.cookies') }
      it { expect(result).not_to have_key('server.request.query') }
      it { expect(result['server.request.uri.raw']).to eq('/health') }
      it { expect(result).not_to have_key('server.request.path_params') }
    end
  end

  describe '.from_response' do
    subject(:result) { described_class.from_response(payload) }

    context 'when payload has status and headers' do
      let(:payload) do
        {
          'statusCode' => 201,
          'headers' => {'Content-Type' => 'application/json', 'Set-Cookie' => 'session=xyz'},
        }
      end

      it { expect(result['server.response.status']).to eq('201') }
      it { expect(result['server.response.headers']).to include('content-type' => 'application/json') }
      it { expect(result['server.response.headers.no_cookies']).not_to have_key('set-cookie') }
    end

    context 'when payload is nil' do
      let(:payload) { nil }

      it { expect(result).to eq({}) }
    end

    context 'when payload is empty' do
      let(:payload) { {} }

      it { expect(result).to eq({}) }
    end

    context 'when statusCode is a string' do
      let(:payload) { {'statusCode' => '404', 'headers' => {}} }

      it { expect(result['server.response.status']).to eq('404') }
    end

    context 'when statusCode is missing' do
      let(:payload) { {'headers' => {}} }

      it { expect(result).not_to have_key('server.response.status') }
    end
  end
end
