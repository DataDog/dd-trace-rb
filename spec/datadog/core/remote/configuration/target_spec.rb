# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/configuration/target'

RSpec.describe Datadog::Core::Remote::Configuration::TargetMap do
  let(:version) { 46761194 }
  let(:opaque_backend_state) { 'eyJ2ZXJzaW9uIjoyLCJzdGF0ZSI6eyJmaWxlX2hhc2hlcyI6eyJkYXRhZG3FOMU44PSJdfX19' }

  # rubocop:disable Layout/LineLength
  let(:raw_target) do
    {
      'signatures' => [
        {
          'keyid' => '44de082b06652b24c3ccfecba7dcbdb82f1cc58e3813f824665a6085a6d6b6a3',
          'sig' => '0a66cbda8de50af143708a8811892786727260b707144b910c07d00e7950d01804835dbd56e789fe8f89f1d0355bb653b8f2a8e41ab90f24d88f2c458438cd00'
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
            'datadog/603646/ASM/blocking/config' => {
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
            },
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
              'hashes' => { 'sha256' => 'c8358ce9038693fb74ad8625e4c6c563bd2afb16b4412b2c8f7dba062e9e88de' },
              'length' => 645
            },
          },
          'version' => version,
        }
    }
  end
  # rubocop:enable Layout/LineLength

  describe '.parse' do
    context 'with valid target hash' do
      it 'returns a TargetMap instance' do
        target_map = described_class.parse(raw_target)
        expect(target_map).to be_a(described_class)

        expect(target_map.opaque_backend_state).to eq(opaque_backend_state)
        expect(target_map.version).to eq(version)
      end

      it 'uses path instances as key and target instance as value' do
        target_map = described_class.parse(raw_target)

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
end

RSpec.describe Datadog::Core::Remote::Configuration::Target do
  let(:raw_target) do
    {
      'custom' =>
        { 'c' => ['854b784e-64ae-4c82-ac9b-fc2aea723260'],
          'tracer-predicates' => { 'tracer_predicates_v1' => [{ 'clientID' => '854b784e-64ae-4c82-ac9b-fc2aea723260' }] },
          'v' => 21 },
      'hashes' => { 'sha256' => 'c8358ce9038693fb74ad8625e4c6c563bd2afb16b4412b2c8f7dba062e9e88de' },
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
        # rubocop:disable Layout/LineLength
        raw = 'eyJleGNsdXNpb25zIjpbeyJjb25kaXRpb25zIjpbeyJvcGVyYXRvciI6ImlwX21hdGNoIiwicGFyYW1ldGVycyI6eyJpbnB1dHMiOlt7ImFkZHJlc3MiOiJodHRwLmNsaWVudF9pcCJ9XSwibGlzdCI6WyI0LjQuNC40Il19fV0sImlkIjoiODc0NDU5YWUtMTM3Zi00Yzk5LTljNTQtMTA5YjFhMTE3Yjg2In0seyJjb25kaXRpb25zIjpbeyJvcGVyYXRvciI6Im1hdGNoX3JlZ2V4IiwicGFyYW1ldGVycyI6eyJpbnB1dHMiOlt7ImFkZHJlc3MiOiJzZXJ2ZXIucmVxdWVzdC51cmkucmF3In1dLCJvcHRpb25zIjp7ImNhc2Vfc2Vuc2l0aXZlIjpmYWxzZX0sInJlZ2V4IjoiXi93YWYifX1dLCJpZCI6ImQxMzkwOTQ5LWNmMWEtNDA4ZC1iYzNmLTA0M2QwNjg5ZDg5ZSJ9LHsiaWQiOiI1ZmU4ZTUzMC1kM2VjLTRlNmQtYmMwNi0wYTY2MzdjNmU3NjMiLCJydWxlc190YXJnZXQiOlt7InJ1bGVfaWQiOiJ1YTAtNjAwLTU1eCJ9XX0seyJjb25kaXRpb25zIjpbeyJvcGVyYXRvciI6ImlwX21hdGNoIiwicGFyYW1ldGVycyI6eyJpbnB1dHMiOlt7ImFkZHJlc3MiOiJodHRwLmNsaWVudF9pcCJ9XSwibGlzdCI6WyI4LjguOC44Il19fV0sImlkIjoiMDgxZTFmYmUtYzczYi00YWQyLWJiODMtNDc1MjM1NDI3MWJjIn1dLCJydWxlc19vdmVycmlkZSI6W119'
        # rubocop:enable Layout/LineLength
        string_io_content = StringIO.new(Base64.strict_decode64(raw).freeze)

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
