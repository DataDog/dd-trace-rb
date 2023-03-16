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
      'hashes' => { 'sha256' => 'c8358ce9038693fb74ad8625e4c6c563bd2afb16b4412b2c8f7dba062e9e88de' },
      'length' => 645
    }
  end

  let(:target) { Datadog::Core::Remote::Configuration::Target.parse(raw_target) }
  let(:path)  { Datadog::Core::Remote::Configuration::Path.parse('datadog/603646/ASM/exclusion_filters/config') }

  # rubocop:disable Layout/LineLength
  let(:raw) { 'eyJleGNsdXNpb25zIjpbeyJjb25kaXRpb25zIjpbeyJvcGVyYXRvciI6ImlwX21hdGNoIiwicGFyYW1ldGVycyI6eyJpbnB1dHMiOlt7ImFkZHJlc3MiOiJodHRwLmNsaWVudF9pcCJ9XSwibGlzdCI6WyI0LjQuNC40Il19fV0sImlkIjoiODc0NDU5YWUtMTM3Zi00Yzk5LTljNTQtMTA5YjFhMTE3Yjg2In0seyJjb25kaXRpb25zIjpbeyJvcGVyYXRvciI6Im1hdGNoX3JlZ2V4IiwicGFyYW1ldGVycyI6eyJpbnB1dHMiOlt7ImFkZHJlc3MiOiJzZXJ2ZXIucmVxdWVzdC51cmkucmF3In1dLCJvcHRpb25zIjp7ImNhc2Vfc2Vuc2l0aXZlIjpmYWxzZX0sInJlZ2V4IjoiXi93YWYifX1dLCJpZCI6ImQxMzkwOTQ5LWNmMWEtNDA4ZC1iYzNmLTA0M2QwNjg5ZDg5ZSJ9LHsiaWQiOiI1ZmU4ZTUzMC1kM2VjLTRlNmQtYmMwNi0wYTY2MzdjNmU3NjMiLCJydWxlc190YXJnZXQiOlt7InJ1bGVfaWQiOiJ1YTAtNjAwLTU1eCJ9XX0seyJjb25kaXRpb25zIjpbeyJvcGVyYXRvciI6ImlwX21hdGNoIiwicGFyYW1ldGVycyI6eyJpbnB1dHMiOlt7ImFkZHJlc3MiOiJodHRwLmNsaWVudF9pcCJ9XSwibGlzdCI6WyI4LjguOC44Il19fV0sImlkIjoiMDgxZTFmYmUtYzczYi00YWQyLWJiODMtNDc1MjM1NDI3MWJjIn1dLCJydWxlc19vdmVycmlkZSI6W119' }
  # rubocop:enable Layout/LineLength

  let(:string_io_content) { StringIO.new(Base64.strict_decode64(raw).freeze) }
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

  describe '#paths' do
    it 'returns an array of paths instance' do
      paths = content_list.paths
      expect(paths.size).to eq(1)
      expect(paths[0].to_s).to eq('datadog/603646/ASM/exclusion_filters/config')
    end
  end
end
