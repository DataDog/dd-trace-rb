# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/aws_lambda/waf_addresses'

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::WAFAddresses do
  describe '.from_request' do
    subject(:result) { described_class.from_request(payload) }

    context 'when payload is API Gateway v1 event' do
      let(:payload) do
        {
          'httpMethod' => 'POST',
          'path' => '/users/123',
          'headers' => {'Host' => 'example.com', 'User-Agent' => 'WebKit', 'Cookie' => 'session=abc'},
          'queryStringParameters' => {'page' => '1'},
          'multiValueQueryStringParameters' => {'page' => ['1']},
          'pathParameters' => {'id' => '123'},
          'body' => '{"name":"john"}',
          'isBase64Encoded' => false,
          'requestContext' => {'identity' => {'sourceIp' => '10.0.0.1'}},
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

    context 'when payload is API Gateway v2 event' do
      let(:payload) do
        {
          'rawPath' => '/users/123',
          'rawQueryString' => 'page=1&sort=asc',
          'headers' => {'host' => 'example.com'},
          'requestContext' => {'http' => {'method' => 'GET', 'sourceIp' => '10.0.0.2'}},
        }
      end

      it { expect(result['server.request.method']).to eq('GET') }
      it { expect(result['server.request.uri.raw']).to eq('/users/123?page=1&sort=asc') }
      it { expect(result['http.client_ip']).to eq('10.0.0.2') }
    end

    context 'when payload has no query string' do
      let(:payload) do
        {
          'path' => '/health',
          'headers' => {},
          'requestContext' => {'identity' => {'sourceIp' => '127.0.0.1'}},
        }
      end

      it { expect(result['server.request.uri.raw']).to eq('/health') }
      it { expect(result['server.request.query']).to eq({}) }
    end

    context 'when payload has no path' do
      let(:payload) { {'headers' => {}, 'requestContext' => {'identity' => {}}} }

      it { expect(result['server.request.uri.raw']).to eq('/') }
    end

    context 'when payload has no method' do
      let(:payload) { {'headers' => {}, 'requestContext' => {'identity' => {}}} }

      it { expect(result['server.request.method']).to eq('GET') }
    end

    context 'when payload has base64-encoded JSON body' do
      let(:payload) do
        {
          'headers' => {'Content-Type' => 'application/json'},
          'body' => Base64.encode64('{"key":"value"}'),
          'isBase64Encoded' => true,
          'requestContext' => {'identity' => {}},
        }
      end

      it { expect(result['server.request.body']).to eq('key' => 'value') }
    end

    context 'when payload has plain JSON body' do
      let(:payload) do
        {
          'headers' => {'Content-Type' => 'application/json'},
          'body' => '{"key":"value"}',
          'isBase64Encoded' => false,
          'requestContext' => {'identity' => {}},
        }
      end

      it { expect(result['server.request.body']).to eq('key' => 'value') }
    end

    context 'when payload has no body' do
      let(:payload) { {'headers' => {}, 'requestContext' => {'identity' => {}}} }

      it { expect(result).not_to have_key('server.request.body') }
    end

    context 'when payload has body with no content-type' do
      let(:payload) do
        {
          'headers' => {},
          'body' => 'some data',
          'requestContext' => {'identity' => {}},
        }
      end

      it { expect(result).not_to have_key('server.request.body') }
    end

    context 'when payload has no path params' do
      let(:payload) { {'headers' => {}, 'requestContext' => {'identity' => {}}} }

      it { expect(result).not_to have_key('server.request.path_params') }
    end

    context 'when cookies have multiple pairs' do
      let(:payload) do
        {
          'headers' => {'Cookie' => 'a=1; b=2; c=val=ue'},
          'requestContext' => {'identity' => {}},
        }
      end

      it { expect(result['server.request.cookies']).to eq('a' => '1', 'b' => '2', 'c' => 'val=ue') }
    end

    context 'when payload has explicit nil fields' do
      let(:payload) do
        {
          'path' => '/health',
          'headers' => nil,
          'queryStringParameters' => nil,
          'multiValueQueryStringParameters' => nil,
          'pathParameters' => nil,
          'requestContext' => {'identity' => {'sourceIp' => '127.0.0.1'}},
        }
      end

      it { expect(result['server.request.headers']).to eq({}) }
      it { expect(result['server.request.headers.no_cookies']).to eq({}) }
      it { expect(result['server.request.cookies']).to eq({}) }
      it { expect(result['server.request.query']).to eq({}) }
      it { expect(result['server.request.uri.raw']).to eq('/health') }
      it { expect(result).not_to have_key('server.request.path_params') }
    end

    context 'when v1 has multiValueQueryStringParameters' do
      let(:payload) do
        {
          'headers' => {},
          'queryStringParameters' => {'a' => '2'},
          'multiValueQueryStringParameters' => {'a' => ['1', '2']},
          'requestContext' => {'identity' => {}},
        }
      end

      it { expect(result['server.request.query']).to eq('a' => ['1', '2']) }
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

      it { expect(result['server.response.status']).to eq('200') }
      it { expect(result['server.response.headers']).to eq({}) }
    end

    context 'when statusCode is a string' do
      let(:payload) { {'statusCode' => '404', 'headers' => {}} }

      it { expect(result['server.response.status']).to eq('404') }
    end

    context 'when statusCode is missing' do
      let(:payload) { {'headers' => {}} }

      it { expect(result['server.response.status']).to eq('200') }
    end
  end
end
