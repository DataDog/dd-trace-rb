require 'spec_helper'

require 'datadog/core/header_collection'
require 'datadog/tracing/client_ip'
require 'datadog/tracing/metadata/ext'

RSpec.describe Datadog::Tracing::ClientIp do
  subject(:client_ip) { described_class }
  let(:tagging_enabled) { true }
  let(:ip_header_name) { nil }

  before do
    Datadog.configure do |c|
      c.tracing.client_ip.enabled = tagging_enabled
      c.tracing.client_ip.header_name = ip_header_name
    end
  end

  after do
    without_warnings { Datadog.configuration.reset! }
  end

  describe '#set_client_ip_tag' do
    let(:span) do
      instance_double('Span')
    end

    context 'when disabled' do
      let(:tagging_enabled) { false }

      it 'does nothing' do
        expect(span).to_not receive(:set_tag)
        client_ip.set_client_ip_tag(span, remote_ip: '15.173.99.139')
      end
    end

    context 'when configured with custom header name' do
      let(:ip_header_name) { 'My-Custom-Header' }
      let(:span) do
        instance_double('Span')
      end

      it 'ignores default header names' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '15.173.99.139' })

        expect(span).to_not receive(:set_tag)
        client_ip.set_client_ip_tag(span, headers: headers)
      end

      it 'uses custom header value as client ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'My-Custom-Header' => '15.173.99.139' })

        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '15.173.99.139')
        client_ip.set_client_ip_tag(span, headers: headers)
      end

      it 'does nothing if custom header value is not a valid ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'My-Custom-Header' => '1.11.1' })

        expect(span).to_not receive(:set_tag)
        client_ip.set_client_ip_tag(span, headers: headers)
      end

      it 'does not use other headers if custom header value is not a valid ip' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          {
            'My-Custom-Header' => '1.11.1',
            'X-Forwarded-For' => '1.11.1'
          }
        )

        expect(span).to_not receive(:set_tag)
        client_ip.set_client_ip_tag(span, headers: headers)
      end

      it 'does not use remote ip if custom header value is not a vaild ip' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          {
            'My-Custom-Header' => '1.11.1',
          }
        )

        expect(span).to_not receive(:set_tag)
        client_ip.set_client_ip_tag(span, headers: headers, remote_ip: '15.173.99.139')
      end

      it 'prefers ip from custom header over remote ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'My-Custom-Header' => '15.173.99.139' })

        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '15.173.99.139')
        client_ip.set_client_ip_tag(span, headers: headers, remote_ip: '2.2.2.2')
      end
    end

    context 'when an ip header is present' do
      it 'uses value from header as client ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '15.173.99.139' })

        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '15.173.99.139')
        client_ip.set_client_ip_tag(span, headers: headers)
      end

      it 'does nothing if header value is not a valid ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '1.11.1' })

        expect(span).to_not receive(:set_tag)
        client_ip.set_client_ip_tag(span, headers: headers)
      end

      it 'uses remote ip if header value is not a valid ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '1.11.1' })

        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '15.173.99.139')
        client_ip.set_client_ip_tag(span, headers: headers, remote_ip: '15.173.99.139')
      end

      it 'prefers ip from header over remote ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '15.173.99.139' })

        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '15.173.99.139')
        client_ip.set_client_ip_tag(span, headers: headers, remote_ip: '2.2.2.2')
      end
    end

    context 'when no ip headers are present' do
      let(:headers) { Datadog::Core::HeaderCollection.from_hash({}) }

      it 'uses remote ip as client ip as fallback' do
        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '15.173.99.139')
        client_ip.set_client_ip_tag(span, headers: headers, remote_ip: '15.173.99.139')
      end

      it 'does nothing if remote ip is invalid' do
        expect(span).to_not receive(:set_tag)
        client_ip.set_client_ip_tag(span, headers: headers, remote_ip: '1.11.1')
      end
    end

    context 'when non-ip headers are present' do
      let(:headers) do
        Datadog::Core::HeaderCollection.from_hash(
          {
            'Accept' => '*/*',
            'Authorization' => 'Bearer XXXXXX'
          }
        )
      end

      it 'uses remote ip as client ip as fallback' do
        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '15.173.99.139')
        client_ip.set_client_ip_tag(span, headers: headers, remote_ip: '15.173.99.139')
      end

      it 'does nothing if remote ip is invalid' do
        expect(span).to_not receive(:set_tag)
        client_ip.set_client_ip_tag(span, headers: headers, remote_ip: '1.11.1')
      end
    end

    context 'when ip' do
      it 'is plain ipv4' do
        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '15.173.99.139')
        client_ip.set_client_ip_tag(span, remote_ip: '15.173.99.139')
      end

      it 'is plain ipv6' do
        expect(span).to receive(:set_tag).with(
          Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP,
          '2001:db8::8a2e:370:7334'
        )
        client_ip.set_client_ip_tag(span, remote_ip: '2001:db8::8a2e:370:7334')
      end

      it 'is ipv4 and port' do
        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '15.173.99.139')
        client_ip.set_client_ip_tag(span, remote_ip: '15.173.99.139:8080')
      end

      it 'is ipv6 and port' do
        expect(span).to receive(:set_tag).with(
          Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP,
          '2001:db8::8a2e:370:7334'
        )
        client_ip.set_client_ip_tag(span, remote_ip: '[2001:db8::8a2e:370:7334]:8080')
      end

      it 'is ipv6 with interface id' do
        expect(span).to receive(:set_tag).with(
          Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP,
          '2001:db8::8a2e:370:7334'
        )
        client_ip.set_client_ip_tag(span, remote_ip: '2001:db8::8a2e:370:7334%eth0')
      end

      it 'is bracketed ipv6 without port' do
        expect(span).to receive(:set_tag).with(
          Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP,
          '2001:db8::8a2e:370:7334'
        )
        client_ip.set_client_ip_tag(span, remote_ip: '[2001:db8::8a2e:370:7334]')
      end
    end
  end
end
