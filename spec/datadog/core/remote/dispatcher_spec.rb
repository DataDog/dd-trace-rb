# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/dispatcher'
require 'datadog/core/remote/configuration/repository'

RSpec.describe Datadog::Core::Remote::Dispatcher do
  let(:matcher) do
    described_class::Matcher.new do |_path|
      true
    end
  end
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
  let(:content) do
    Datadog::Core::Remote::Configuration::Content.parse({ path: path.to_s, content: string_io_content })
  end
  let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }

  let(:receiver_block) { proc { |_repository, _changes| } }

  let(:receiver) do
    described_class::Receiver.new(matcher, &receiver_block)
  end

  subject(:dispatcher) do
    d = described_class.new
    d.receivers << receiver
    d
  end

  describe '#dispatch' do
    context 'receiver matches' do
      it 'dispatches #call on matched changes' do
        changes = repository.transaction do |_repository, transaction|
          transaction.insert(path, target, content)
        end

        expect(receiver).to receive(:call).with(
          repository,
          [instance_of(Datadog::Core::Remote::Configuration::Repository::Change::Inserted)]
        )

        dispatcher.dispatch(changes, repository)
      end
    end

    context 'receiver does not matches' do
      let(:matcher) do
        described_class::Matcher.new do |_path|
          false
        end
      end

      it 'does not dispatches #call on non matched changes' do
        changes = repository.transaction do |_repository, transaction|
          transaction.insert(path, target, content)
        end

        expect(receiver).to_not receive(:call).with(
          repository,
          [instance_of(Datadog::Core::Remote::Configuration::Repository::Change::Inserted)]
        )

        dispatcher.dispatch(changes, repository)
      end
    end
  end

  describe Datadog::Core::Remote::Dispatcher::Matcher::Product do
    subject(:matcher) { described_class.new([product]) }

    context 'matches' do
      let(:product) { 'ASM' }

      it 'returns true' do
        expect(matcher).to be_match(path)
      end
    end

    context 'does not match' do
      let(:product) { 'FAKE_PRODUCT' }

      it 'returns false' do
        expect(matcher).not_to be_match(path)
      end
    end
  end
end
