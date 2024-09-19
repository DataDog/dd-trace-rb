require 'spec_helper'

require 'datadog/core/utils/network'

RSpec.describe Datadog::Core::Utils::Network do
  describe '.stripped_ip_from_request_headers' do
    context 'with default IP headers' do
      context 'iterates over the default headers (DEFAULT_IP_HEADERS_NAMES) in order' do
        it 'returns the first valid public IP value' do
          headers = Datadog::Core::HeaderCollection.from_hash(
            { 'X-Forwarded-For' => '10.42.42.42',
              'True-Client-Ip' => '43.43.43.43',
              'X-Cluster-Client-Ip' => '10.0.0.1', }
          )

          result = described_class.stripped_ip_from_request_headers(headers)
          expect(result).to eq('43.43.43.43')
        end
      end

      context 'multiple IP addresses present in the header' do
        it 'returns the first valid public IP address' do
          headers = Datadog::Core::HeaderCollection.from_hash({ 'X-Forwarded-For' => '10.42.42.42,43.43.43.43,fe80::1' })

          result = described_class.stripped_ip_from_request_headers(headers)
          expect(result).to eq('43.43.43.43')
        end
      end

      context 'with custom header value' do
        it 'returns the IP value if valid public address' do
          headers = Datadog::Core::HeaderCollection.from_hash(
            {
              'X-Forwarded-For' => '64.233.161.147',
              'test-header' => '43.43.43.43',
            }
          )

          result = described_class.stripped_ip_from_request_headers(headers, ip_headers_to_check: ['test-header'])
          expect(result).to eq('43.43.43.43')
        end

        it 'returns nil if header not present' do
          headers = Datadog::Core::HeaderCollection.from_hash({})

          result = described_class.stripped_ip_from_request_headers(headers, ip_headers_to_check: ['test-header'])
          expect(result).to be_nil
        end

        it 'returns nil if header value is not valid' do
          headers = Datadog::Core::HeaderCollection.from_hash({ 'test-header' => 'dd' })

          result = described_class.stripped_ip_from_request_headers(headers, ip_headers_to_check: ['test-header'])
          expect(result).to be_nil
        end
      end

      it 'returns nil if no public valid IP addresss present in the headers' do
        headers = Datadog::Core::HeaderCollection.from_hash(
          { 'X-Forwarded-For' => '10.42.42.42' }
        )

        result = described_class.stripped_ip_from_request_headers(headers)
        expect(result).to be_nil
      end
    end
  end

  describe '.stripped_ip' do
    context 'valid IP' do
      it 'returns the IP value, with port and zone identifier removed' do
        ips =
          [
            ['10.0.0.0', '10.0.0.0'],
            ['10.0.0.1', '10.0.0.1'],
            ['10.0.0.1:8080', '10.0.0.1'],
            ['1080:0000:0000:0000:0008:0800:200C:417A', '1080::8:800:200c:417a'],
            ['1080:0:0:0:8:800:200C:417A', '1080::8:800:200c:417a'],
            ['1080:0::8:800:200C:417A', '1080::8:800:200c:417a'],
            ['1080::8:800:200C:417A', '1080::8:800:200c:417a'],
            ['FF01:0:0::0:0:43', 'ff01::43'],
            ['FF01::43', 'ff01::43'],
            ['fe80::208:74ff:feda:625c', 'fe80::208:74ff:feda:625c'],
            ['fe80::208:74ff:feda:625c%eth0', 'fe80::208:74ff:feda:625c'],
            ['ff80:03:02:01::', 'ff80:3:2:1::'],
            ['[fe80::208:74ff:feda:625c]', 'fe80::208:74ff:feda:625c'],
            ['[fe80::208:74ff:feda:625c]:8080', 'fe80::208:74ff:feda:625c'],
            ['[fe80::208:74ff:feda:625c%eth0]:8080', 'fe80::208:74ff:feda:625c'],
          ]

        ips.each do |ip, expected_result|
          result = described_class.stripped_ip(ip)
          expect(result).to eq(expected_result)
        end
      end
    end

    context 'invalid IP' do
      it 'returns nil' do
        ips =
          [
            '',
            'dd',
            '02001:0000:1234:0000:0000:C1C0:ABCD:0876',
            '2001:0000:1234:0000:00001:C1C0:ABCD:0876'
          ]

        ips.each do |ip|
          result = described_class.stripped_ip(ip)
          expect(result).to be_nil
        end
      end
    end
  end
end
