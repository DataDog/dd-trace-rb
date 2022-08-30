require 'spec_helper'

require 'datadog/core/header_collection'
require 'datadog/tracing/client_ip'
require 'datadog/tracing/metadata/ext'

RSpec::Matchers.define :be_valid_ip do
  match do |actual|
    normalised = Datadog::Tracing::ClientIp.strip_decorations(actual)
    begin
      Datadog::Tracing::ClientIp.validate_ip(normalised)

      true
    rescue Datadog::Tracing::ClientIp::InvalidIpError
      false
    end
  end
end

RSpec.describe Datadog::Tracing::ClientIp do
  subject(:client_ip) { described_class }
  let(:tagging_enabled) { true }
  let(:ip_header_name) { nil }

  before do
    Datadog.configure do |c|
      c.tracing.client_ip.disabled = !tagging_enabled
      c.tracing.client_ip.header_name = ip_header_name
    end
  end

  after do
    without_warnings { Datadog.configuration.reset! }
  end

  describe 'ip validation' do
    context 'when given valid ip addresses' do
      subject do
        [
          '10.0.0.0',
          '10.0.0.1',
          '10.0.0.1:8080',
          'FEDC:BA98:7654:3210:FEDC:BA98:7654:3210',
          '1080:0000:0000:0000:0008:0800:200C:417A',
          '1080:0:0:0:8:800:200C:417A',
          '1080:0::8:800:200C:417A',
          '1080::8:800:200C:417A',
          'FF01:0:0:0:0:0:0:43',
          'FF01:0:0::0:0:43',
          'FF01::43',
          '0:0:0:0:0:0:0:1',
          '0:0:0::0:0:1',
          '::1',
          '0:0:0:0:0:0:0:0',
          '0:0:0::0:0:0',
          '::',
          'fe80::208:74ff:feda:625c',
          'fe80::208:74ff:feda:625c%eth0',
          'ff80:03:02:01::',
          '[fe80::208:74ff:feda:625c]',
          '[fe80::208:74ff:feda:625c]:8080',
          '[fe80::208:74ff:feda:625c%eth0]:8080'
        ]
      end

      it { is_expected.to all(be_valid_ip) }
    end

    context 'when given invalid ip addresses' do
      subject do
        [
          '',
          '10.0.0.256',
          '10.0.0.0.0',
          '10.0.0',
          '10.0',
          '0.0.0.0/0',
          '10.0.0.1/24',
          '10.0.0.1/255.255.255.0',
          ':1:2:3:4:5:6:7',
          ':1:2:3:4:5:6:7',
          '2002:516:2:200',
          'dd',
          '2001:db8::8:800:200c:417a/64',
          '02001:0000:1234:0000:0000:C1C0:ABCD:0876',
          '2001:0000:1234:0000:00001:C1C0:ABCD:0876'
        ]
      end

      it { is_expected.to_not include(be_valid_ip) }
    end
  end

  describe '#set_client_ip_tag' do
    let(:span) do
      instance_double('Span')
    end

    context 'when disabled' do
      let(:tagging_enabled) { false }

      it 'does nothing' do
        expect(span).to_not receive(:set_tag).with(any_args)
        client_ip.set_client_ip_tag(span, nil, '1.1.1.1')
      end
    end

    context 'when configured with custom header name' do
      let(:ip_header_name) { 'My-Custom-Header' }
      let(:span) do
        instance_double('Span')
      end

      it 'ignores default header names' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '1.1.1.1' })

        expect(span).to_not receive(:set_tag).with(any_args)
        client_ip.set_client_ip_tag(span, headers, nil)
      end

      it 'uses custom header value as client ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'My-Custom-Header' => '1.1.1.1' })

        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '1.1.1.1')
        client_ip.set_client_ip_tag(span, headers, nil)
      end

      it 'does nothing if custom header value is not a valid ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'My-Custom-Header' => '1.11.1' })

        expect(span).to_not receive(:set_tag).with(any_args)
        client_ip.set_client_ip_tag(span, headers, nil)
      end

      it 'does not use other headers if custom header value is not a valid ip' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          {
            'My-Custom-Header' => '1.11.1',
            'X-Forwarded-For' => '1.11.1'
          }
        )

        expect(span).to_not receive(:set_tag).with(any_args)
        client_ip.set_client_ip_tag(span, headers, nil)
      end

      it 'does not use remote ip if custom header value is not a vaild ip' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          {
            'My-Custom-Header' => '1.11.1',
          }
        )

        expect(span).to_not receive(:set_tag).with(any_args)
        client_ip.set_client_ip_tag(span, headers, '1.1.1.1')
      end

      it 'prefers ip from custom header over remote ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'My-Custom-Header' => '1.1.1.1' })

        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '1.1.1.1')
        client_ip.set_client_ip_tag(span, headers, '2.2.2.2')
      end
    end

    context 'when single ip header is present' do
      it 'uses value from header as client ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '1.1.1.1' })

        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '1.1.1.1')
        client_ip.set_client_ip_tag(span, headers, nil)
      end

      it 'does nothing if header value is not a valid ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '1.11.1' })

        expect(span).to_not receive(:set_tag).with(any_args)
        client_ip.set_client_ip_tag(span, headers, nil)
      end

      it 'does not use remote ip if header value is not a valid ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '1.11.1' })

        expect(span).to_not receive(:set_tag).with(any_args)
        client_ip.set_client_ip_tag(span, headers, '1.1.1.1')
      end

      it 'prefers ip from header over remote ip' do
        headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '1.1.1.1' })

        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '1.1.1.1')
        client_ip.set_client_ip_tag(span, headers, '2.2.2.2')
      end
    end

    context 'when multiple ip headers are present' do
      it 'sets multiple ip headers tag only' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          {
            'X-Forwarded-For' => '1.1.1.1',
            'X-Client-Ip' => '2.2.2.2'
          }
        )

        expect(span).to_not receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, anything)
        expect(span).to receive(:set_tag).with(client_ip::TAG_MULTIPLE_IP_HEADERS, 'x-forwarded-for,x-client-ip')
        client_ip.set_client_ip_tag(span, headers, nil)
      end

      it 'sets multiple ip headers tag only even if all ips are the same' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          {
            'X-Forwarded-For' => '1.1.1.1',
            'X-Client-Ip' => '1.1.1.1'
          }
        )

        expect(span).to_not receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, anything)
        expect(span).to receive(:set_tag).with(client_ip::TAG_MULTIPLE_IP_HEADERS, 'x-forwarded-for,x-client-ip')
        client_ip.set_client_ip_tag(span, headers, nil)
      end

      it 'prefers multiple ip headers tag only over remote ip' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          {
            'X-Forwarded-For' => '1.1.1.1',
            'X-Client-Ip' => '2.2.2.2'
          }
        )

        expect(span).to_not receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, anything)
        expect(span).to receive(:set_tag).with(client_ip::TAG_MULTIPLE_IP_HEADERS, 'x-forwarded-for,x-client-ip')
        client_ip.set_client_ip_tag(span, headers, '3.3.3.3')
      end

      it 'includes ip headers with invalid ips in multiple ip headers tag' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          {
            'X-Forwarded-For' => '1.1.1.1',
            'X-Client-Ip' => '2.2.2.2.3',
            'X-Real-Ip' => '3.3.3.3'
          }
        )

        expect(span).to_not receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, anything)
        expect(span).to receive(:set_tag).with(client_ip::TAG_MULTIPLE_IP_HEADERS, 'x-forwarded-for,x-real-ip,x-client-ip')
        client_ip.set_client_ip_tag(span, headers, nil)
      end

      it 'includes ip headers with invalid ips in multiple ip headers tag even if exactly one ip is valid' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          {
            'X-Forwarded-For' => '1.1.1.1',
            'X-Client-Ip' => '2.22.2',
            'X-Real-Ip' => 'dd'
          }
        )

        expect(span).to_not receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, anything)
        expect(span).to receive(:set_tag).with(client_ip::TAG_MULTIPLE_IP_HEADERS, 'x-forwarded-for,x-real-ip,x-client-ip')
        client_ip.set_client_ip_tag(span, headers, nil)
      end
    end

    context 'when no ip headers are present' do
      let(:headers) { Datadog::Core::HeaderCollection.from_hash({}) }

      it 'uses remote ip as client ip as fallback' do
        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '1.1.1.1')
        client_ip.set_client_ip_tag(span, headers, '1.1.1.1')
      end

      it 'does nothing if remote ip is invalid' do
        expect(span).to_not receive(:set_tag).with(any_args)
        client_ip.set_client_ip_tag(span, headers, '1.11.1')
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
        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '1.1.1.1')
        client_ip.set_client_ip_tag(span, headers, '1.1.1.1')
      end

      it 'does nothing if remote ip is invalid' do
        expect(span).to_not receive(:set_tag).with(any_args)
        client_ip.set_client_ip_tag(span, headers, '1.11.1')
      end
    end

    context 'when ip' do
      it 'is plain ipv4' do
        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '1.1.1.1')
        client_ip.set_client_ip_tag(span, nil, '1.1.1.1')
      end

      it 'is plain ipv6' do
        expect(span).to receive(:set_tag).with(
          Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP,
          '2001:db8::8a2e:370:7334'
        )
        client_ip.set_client_ip_tag(span, nil, '2001:db8::8a2e:370:7334')
      end

      it 'is ipv4 and port' do
        expect(span).to receive(:set_tag).with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, '1.1.1.1')
        client_ip.set_client_ip_tag(span, nil, '1.1.1.1:8080')
      end

      it 'is ipv6 and port' do
        expect(span).to receive(:set_tag).with(
          Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP,
          '2001:db8::8a2e:370:7334'
        )
        client_ip.set_client_ip_tag(span, nil, '[2001:db8::8a2e:370:7334]:8080')
      end

      it 'is ipv6 with interface id' do
        expect(span).to receive(:set_tag).with(
          Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP,
          '2001:db8::8a2e:370:7334'
        )
        client_ip.set_client_ip_tag(span, nil, '2001:db8::8a2e:370:7334%eth0')
      end

      it 'is bracketed ipv6 without port' do
        expect(span).to receive(:set_tag).with(
          Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP,
          '2001:db8::8a2e:370:7334'
        )
        client_ip.set_client_ip_tag(span, nil, '[2001:db8::8a2e:370:7334]')
      end
    end
  end
end
