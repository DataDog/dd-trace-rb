# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/configuration/content'
require 'datadog/core/remote/configuration/target'

RSpec.describe Datadog::Core::Remote::Configuration::ContentList do
  let(:raw_target) do
    {
      'custom' =>
        { 'c' => ['854b784e-64ae-4c82-ac9b-fc2aea723260'],
          'tracer-predicates' => { 'tracer_predicates_v1' => [{ 'clientID' => '854b784e-64ae-4c82-ac9b-fc2aea723260' }] },
          'v' => 21 },
      'hashes' => { 'sha256' => Digest::SHA256.hexdigest(raw.to_json) },
      'length' => 645
    }
  end

  let(:target) { Datadog::Core::Remote::Configuration::Target.parse(raw_target) }
  let(:path) { Datadog::Core::Remote::Configuration::Path.parse('datadog/603646/ASM/exclusion_filters/config') }

  let(:raw) do
    {
      exclusions: [
        {
          conditions: [
            {
              operator: 'ip_match',
              parameters: {
                inputs: [
                  {
                    address: 'http.client_ip'
                  }
                ],
                list: [
                  '4.4.4.4'
                ]
              }
            }
          ],
          id: '874459ae-137f-4c99-9c54-109b1a117b86'
        },
        {
          conditions: [
            {
              operator: 'match_regex',
              parameters: {
                inputs: [
                  {
                    address: 'server.request.uri.raw'
                  }
                ],
                options: {
                  case_sensitive: false
                },
                regex: '^/waf'
              }
            }
          ],
          id: 'd1390949-cf1a-408d-bc3f-043d0689d89e'
        },
        {
          id: '5fe8e530-d3ec-4e6d-bc06-0a6637c6e763',
          rules_target: [
            {
              rule_id: 'ua0-600-55x'
            }
          ]
        },
        {
          conditions: [
            {
              operator: 'ip_match',
              parameters: {
                inputs: [
                  {
                    address: 'http.client_ip'
                  }
                ],
                list: [
                  '8.8.8.8'
                ]
              }
            }
          ],
          id: '081e1fbe-c73b-4ad2-bb83-4752354271bc'
        }
      ],
      rules_override: []
    }
  end
  let(:string_io_content) { StringIO.new(raw.to_json) }
  subject(:content_list) do
    described_class.parse(
      [{
        :path => path.to_s,
        :content => string_io_content
      }]
    )
  end

  describe '.parse' do
    context 'valid data' do
      it 'returns a ContentList instance' do
        expect(content_list).to be_a(described_class)
      end
    end

    context 'invalid data' do
      it 'raises Path::ParseError' do
        expect do
          described_class.parse(
            [{
              :path => 'invalid path',
              :content => string_io_content
            }]
          )
        end.to raise_error(Datadog::Core::Remote::Configuration::Path::ParseError)
      end
    end
  end

  describe '#find_content' do
    it 'returns a content instance if path and target matches' do
      content = content_list.find_content(path, target)
      expect(content).to be_a(Datadog::Core::Remote::Configuration::Content)
    end

    it 'returns nil if does not find a valid path' do
      non_existing_path = Datadog::Core::Remote::Configuration::Path.parse('employee/ASM/exclusion_filters/config')

      content = content_list.find_content(non_existing_path, target)
      expect(content).to be_nil
    end

    it 'returns nil if target does not check' do
      wrong_target = Datadog::Core::Remote::Configuration::Target.parse(
        {
          'custom' => {
            'c' => ['5bb79ec4-0f50-464c-8400-b88521e1b96e'],
            'tracer-predicates' => {
              'tracer_predicates_v1' => [
                {
                  'clientID' => '5bb79ec4-0f50-464c-8400-b88521e1b96e'
                }
              ]
            },
            'v' => 245
          },
          'hashes' => { 'sha256' => 'e39c699e5e626da1a43369ab3e7f17cce6a21c0ce1d2261280c7f2ac61c5db1b' },
          'length' => 4605
        }
      )

      content = content_list.find_content(path, wrong_target)
      expect(content).to be_nil
    end
  end

  describe '#[]' do
    it 'returns a content instance if path matches' do
      content = content_list[path]
      expect(content).to be_a(Datadog::Core::Remote::Configuration::Content)
    end

    it 'returns nil if doesn not find a match' do
      non_existing_path = Datadog::Core::Remote::Configuration::Path.parse('employee/ASM/exclusion_filters/config')

      content = content_list[non_existing_path]
      expect(content).to be_nil
    end
  end

  describe '#[]=' do
    let(:updated_string_io) { StringIO.new('Hello World') }
    let(:updated_content) do
      Datadog::Core::Remote::Configuration::Content.parse(
        {
          :path => path.to_s,
          :content => updated_string_io
        }
      )
    end

    it 'replaces content for an existing path' do
      content = content_list[path]
      expect(content.data).to eq(string_io_content)
      content_list[path] = updated_content

      content = content_list[path]
      expect(content.data).to eq(updated_string_io)
    end

    it 'if path does not match does not updates it' do
      non_existing_path = Datadog::Core::Remote::Configuration::Path.parse('employee/ASM/exclusion_filters/config')

      content_list[non_existing_path] = updated_content
      expect(content_list[non_existing_path]).to be_nil
    end
  end

  describe '#delete' do
    it 'removes content from list' do
      content = content_list[path]
      expect(content.data).to eq(string_io_content)

      expect(content_list.delete(path)).to eq(content)

      expect(content_list[path]).to be_nil
    end

    it 'if path does not exists returns nil' do
      non_existing_path = Datadog::Core::Remote::Configuration::Path.parse('employee/ASM/exclusion_filters/config')

      expect(content_list.delete(non_existing_path)).to be_nil
    end
  end

  describe '#paths' do
    it 'returns an array of paths instance' do
      paths = content_list.paths
      expect(paths.size).to eq(1)
      expect(paths[0].to_s).to eq('datadog/603646/ASM/exclusion_filters/config')
    end
  end

  describe Datadog::Core::Remote::Configuration::Content do
    subject(:content) do
      described_class.parse(
        {
          :path => path.to_s,
          :content => string_io_content
        }
      )
    end

    describe '#hashes' do
      context 'when no hash has been computed' do
        it 'return {}' do
          expect(content.hashes).to eq({})
        end
      end
    end

    describe '#hexdigest' do
      before do
        content.hexdigest(:sha256)
        content.hexdigest(:sha512)
      end

      context 'compute hash of content' do
        it 'returns hash value' do
          expect(content.hexdigest(:sha256)).to eq('c8358ce9038693fb74ad8625e4c6c563bd2afb16b4412b2c8f7dba062e9e88de')
        end

        it 'stores the value in hashes' do
          expect(content.hashes).to eq(
            {
              :sha256 => 'c8358ce9038693fb74ad8625e4c6c563bd2afb16b4412b2c8f7dba062e9e88de',
              :sha512 => '546b5325ec8559dda0b34f3e628e99c7b9d18eb59b23ec87f672b1ed8c4ac9ac'\
                '11ac6ffb15e6b4d71f5f343ec243d142db61aaf60f4a0410e39dc916c623cc82'
            }
          )
        end
      end
    end

    describe '#applied' do
      subject(:applied) { content.applied }

      it 'sets applied_state to acknowledged' do
        applied
        expect(content.apply_state).to eq(2)
      end

      it 'clear errors' do
        content.errored('error message')

        applied

        expect(content.apply_error).to be_nil
      end
    end

    describe '#errored' do
      subject(:errored) { content.errored(message) }
      let(:message) { 'test-message' }

      it 'sets applied_state to error with message' do
        errored
        expect(content.apply_state).to eq(3)
        expect(content.apply_error).to eq('test-message')
      end
    end
  end
end
