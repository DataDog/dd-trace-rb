# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/configuration/target'

RSpec.describe Datadog::Core::Remote::Configuration::TargetMap do
  let(:version) { 46761194 }
  let(:opaque_backend_state) { 'eyJ2ZXJzaW9uIjoyLCJzdGF0ZSI6eyJmaWxlX2hhc2hlcyI6eyJkYXRhZG3FOMU44PSJdfX19' }
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

  let(:raw_target_map) do
    {
      'signatures' => [
        {
          'keyid' => '44de082b06652b24c3ccfecba7dcbdb82f1cc58e3813f824665a6085a6d6b6a3',
          'sig' => '0a66cbda8de50af143708a8811892786727260b707144b910c07d00e7950d'
        }
      ],
      'signed' =>
        {
          '_type' => 'targets',
          'custom' => {
            'agent_refresh_interval' => 50,
            'opaque_backend_state' => opaque_backend_state
          },
          'expires' => '2023-06-15T15:25:56Z',
          'spec_version' => '1.0.0',
          'targets' => {
            'datadog/603646/ASM/exclusion_filters/config' => {
              'custom' => {
                'c' => ['5bb79ec4-0f50-464c-8400-b88521e1b96e'],
                'tracer-predicates' => {
                  'tracer_predicates_v1' => [
                    {
                      'clientID' => '5bb79ec4-0f50-464c-8400-b88521e1b96e'
                    }
                  ]
                }, 'v' => 21
              },
              'hashes' => { 'sha256' => Digest::SHA256.hexdigest(raw.to_json) },
              'length' => 645
            },
          },
          'version' => version,
        }
    }
  end
  describe '.parse' do
    context 'with valid target hash' do
      it 'returns a TargetMap instance' do
        target_map = described_class.parse(raw_target_map)
        expect(target_map).to be_a(described_class)

        expect(target_map.opaque_backend_state).to eq(opaque_backend_state)
        expect(target_map.version).to eq(version)
      end

      it 'uses path instances as key and target instance as value' do
        target_map = described_class.parse(raw_target_map)

        path = Datadog::Core::Remote::Configuration::Path.parse('datadog/603646/ASM/exclusion_filters/config')
        expect(target_map[path]).to be_a(Datadog::Core::Remote::Configuration::Target)

        not_present_path = Datadog::Core::Remote::Configuration::Path.parse('employee/ASM_DD/17.recommended.json/config')
        expect(target_map[not_present_path]).to be_nil
      end
    end

    context 'with valid target path' do
      it 'raises Path::ParseError' do
        invalid_data = {
          'signatures' => [
            {
              'keyid' => '44de082b06652b24c3ccfecba7dcbdb82f1cc58e3813f824665a6085a6d6b6a3',
              'sig' => '0a66cbda8de50af143708a881189278672'
            }
          ],
          'signed' =>
            {
              '_type' => 'targets',
              'custom' => {
                'agent_refresh_interval' => 50,
                'opaque_backend_state' => opaque_backend_state
              },
              'expires' => '2023-06-15T15:25:56Z',
              'spec_version' => '1.0.0',
              'targets' => {
                'invalid_path' => {}
              },
              'version' => version,
            }
        }

        expect { described_class.parse(invalid_data) }.to raise_error(
          Datadog::Core::Remote::Configuration::Path::ParseError
        )
      end
    end
  end

  describe Datadog::Core::Remote::Configuration::Target do
    let(:raw_target) do
      {
        'custom' => {
          'v' => 1,
        },
        'hashes' => { 'sha256' => Digest::SHA256.hexdigest(raw.to_json) },
        'length' => 645
      }
    end

    subject(:target) { described_class.parse(raw_target) }

    describe '.parse' do
      context 'with valid target' do
        it 'returns a Target instance' do
          expect(target).to be_a(described_class)
        end
      end
    end

    describe '#check' do
      context 'valid content' do
        it 'returns true' do
          string_io_content = StringIO.new(raw.to_json)

          content_hash = {
            :path => 'datadog/603646/ASM/exclusion_filters/config',
            :content => string_io_content
          }
          content = Datadog::Core::Remote::Configuration::Content.parse(content_hash)

          expect(target.check(content)).to be_truthy
        end
      end

      context 'invalid content' do
        it 'returns false' do
          content_hash = {
            :path => 'datadog/603646/ASM/exclusion_filters/config',
            :content => StringIO.new('Hello World')
          }
          content = Datadog::Core::Remote::Configuration::Content.parse(content_hash)

          expect(target.check(content)).to be_falsy
        end
      end
    end
  end
end
