# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/configuration/repository'
require 'datadog/core/remote/configuration/target'

RSpec.describe Datadog::Core::Remote::Configuration::Repository do
  subject(:repository) { described_class.new }
  let(:raw_target) do
    {
      'custom' => {
        'v' => 1,
      },
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

  let(:new_content_string_io_content) { StringIO.new('hello world') }

  let(:new_content) do
    Datadog::Core::Remote::Configuration::Content.parse(
      {
        path: path.to_s,
        content: new_content_string_io_content
      }
    )
  end

  let(:new_target) do
    updated_raw_target = raw_target.dup
    updated_raw_target['custom']['v'] += 1
    Datadog::Core::Remote::Configuration::Target.parse(updated_raw_target)
  end

  describe '#transaction' do
    it 'yields self and a new Repository::Transaction instance' do
      expect do |b|
        repository.transaction(&b)
      end.to yield_with_args(
        repository,
        instance_of(Datadog::Core::Remote::Configuration::Repository::Transaction)
      )
    end

    it 'commits transaction' do
      expect(repository).to receive(:commit).with(
        instance_of(Datadog::Core::Remote::Configuration::Repository::Transaction)
      )
      repository.transaction(&proc {})
    end

    describe 'set operation' do
      it 'set values and do not report changes' do
        expect(repository.opaque_backend_state).to be_nil
        expect(repository.targets_version).to eq(0)

        changes = repository.transaction do |_repository, transaction|
          transaction.set(opaque_backend_state: '1', targets_version: 3)
        end

        expect(repository.opaque_backend_state).to eq('1')
        expect(repository.targets_version).to eq(3)
        expect(changes).to be_a(Datadog::Core::Remote::Configuration::Repository::ChangeSet)
        expect(changes.size).to eq(0)
      end
    end

    describe 'insert operation' do
      it 'store content and return ChangeSet instance' do
        expect(repository.contents.size).to eq(0)

        changes = repository.transaction do |_repository, transaction|
          transaction.insert(path, target, content)
        end

        expect(repository.contents.size).to eq(1)
        expect(changes).to be_a(Datadog::Core::Remote::Configuration::Repository::ChangeSet)
        expect(changes.size).to eq(1)
        expect(changes.first).to be_a(Datadog::Core::Remote::Configuration::Repository::Change::Inserted)
      end

      it 'does not store same path twice' do
        expect(repository.contents.size).to eq(0)

        changes = repository.transaction do |_repository, transaction|
          transaction.insert(path, target, content)
          transaction.insert(path, target, content)
        end

        expect(repository.contents.size).to eq(1)
        expect(changes).to be_a(Datadog::Core::Remote::Configuration::Repository::ChangeSet)
        expect(changes.size).to eq(1)
        expect(changes.first).to be_a(Datadog::Core::Remote::Configuration::Repository::Change::Inserted)
      end
    end

    describe 'update operation' do
      it 'change the path\'s content and return ChangeSet instance' do
        expect(repository.contents.size).to eq(0)

        changes = repository.transaction do |_repository, transaction|
          transaction.insert(path, target, content)
        end

        expect(repository.contents[path]).to eq(content)

        new_content = Datadog::Core::Remote::Configuration::Content.parse(
          { path: path.to_s,
            content: StringIO.new('hello world') }
        )

        updated_changes = repository.transaction do |_repository, transaction|
          transaction.update(path, target, new_content)
        end
        expect(changes).to_not eq(updated_changes)
        expect(repository.contents[path]).to eq(new_content)
        expect(updated_changes.size).to eq(1)
        expect(updated_changes.first).to be_a(Datadog::Core::Remote::Configuration::Repository::Change::Updated)
      end

      it 'does not change the path\'s content if path doesn not exists' do
        expect(repository.contents.size).to eq(0)

        repository.transaction do |_repository, transaction|
          transaction.insert(path, target, content)
        end

        expect(repository.contents[path]).to eq(content)
        new_path = Datadog::Core::Remote::Configuration::Path.parse('employee/ASM/exclusion_filters/config')
        new_content = Datadog::Core::Remote::Configuration::Content.parse(
          { path: new_path.to_s,
            content: StringIO.new('hello world') }
        )

        changes = repository.transaction do |_repository, transaction|
          transaction.update(new_path, target, new_content)
        end

        expect(repository.contents.size).to eq(1)
        expect(repository.contents[path]).to eq(content)
        expect(changes).to be_a(Datadog::Core::Remote::Configuration::Repository::ChangeSet)
        expect(changes.size).to eq(0)
      end
    end

    describe 'delete operation' do
      it 'delete existing content base on path and return ChangeSet instance' do
        expect(repository.contents.size).to eq(0)

        repository.transaction do |_repository, transaction|
          transaction.insert(path, target, content)
        end

        expect(repository.contents[path]).to eq(content)

        changes = repository.transaction do |_repository, transaction|
          transaction.delete(path)
        end

        expect(repository.contents[path]).to be_nil
        expect(changes).to be_a(Datadog::Core::Remote::Configuration::Repository::ChangeSet)
        expect(changes.size).to eq(1)
        expect(changes.first).to be_a(Datadog::Core::Remote::Configuration::Repository::Change::Deleted)
      end

      it 'does not delete content if path does not match' do
        expect(repository.contents.size).to eq(0)

        repository.transaction do |_repository, transaction|
          transaction.insert(path, target, content)
        end

        expect(repository.contents[path]).to eq(content)

        new_path = Datadog::Core::Remote::Configuration::Path.parse('employee/ASM/exclusion_filters/config')

        changes = repository.transaction do |_repository, transaction|
          transaction.delete(new_path)
        end

        expect(repository.contents[path]).to eq(content)
        expect(changes).to be_a(Datadog::Core::Remote::Configuration::Repository::ChangeSet)
        expect(changes.size).to eq(0)
      end
    end
  end

  describe '#state' do
    it 'returns a state instance' do
      expect(repository.state).to be_a(described_class::State)
    end
  end

  describe Datadog::Core::Remote::Configuration::Repository::State do
    let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }

    describe '#cached_target_files' do
      context 'without changes' do
        it 'return empty array' do
          expect(repository.state.cached_target_files).to eq([])
        end
      end

      context 'with changes' do
        before do
          content.hexdigest(:sha256)
          new_content.hexdigest(:sha256)
        end

        let(:expected_cached_target_files) do
          [
            {
              hashes: [
                {
                  algorithm: :sha256,
                  hash: content.hexdigest(:sha256)
                }
              ],
              length: 645,
              path: 'datadog/603646/ASM/exclusion_filters/config'
            }
          ]
        end

        context 'insert' do
          it 'return cached_target_files' do
            repository.transaction do |_repository, transaction|
              transaction.insert(path, target, content)
            end

            expect(repository.state.cached_target_files).to eq(expected_cached_target_files)
          end
        end

        context 'update' do
          it 'return cached_target_files' do
            repository.transaction do |_repository, transaction|
              transaction.insert(path, target, content)
            end

            expect(repository.state.cached_target_files).to eq(expected_cached_target_files)

            repository.transaction do |_repository, transaction|
              transaction.update(path, target, new_content)
            end

            expected_updated_cached_target_files = [
              {
                hashes: [
                  {
                    algorithm: :sha256,
                    hash: new_content.hexdigest(:sha256)
                  }
                ],
                length: new_content_string_io_content.length,
                path: 'datadog/603646/ASM/exclusion_filters/config'
              }
            ]

            expect(repository.state.cached_target_files).to_not eq(expected_cached_target_files)
            expect(repository.state.cached_target_files).to eq(expected_updated_cached_target_files)
          end
        end

        context 'delete' do
          it 'return cached_target_files' do
            repository.transaction do |_repository, transaction|
              transaction.insert(path, target, content)
            end

            expect(repository.state.cached_target_files).to eq(expected_cached_target_files)

            repository.transaction do |_repository, transaction|
              transaction.delete(path)
            end

            expect(repository.state.cached_target_files).to eq([])
          end
        end
      end
    end

    describe '#config_states' do
      context 'without changes' do
        it 'return empty array' do
          expect(repository.state.config_states).to eq([])
        end
      end

      context 'with changes' do
        let(:expected_config_states) do
          [
            { id: path.config_id, product: path.product, version: 1, apply_error: nil, apply_state: 1 }
          ]
        end

        context 'insert' do
          it 'return config_states' do
            repository.transaction do |_repository, transaction|
              transaction.insert(path, target, content)
            end

            expect(repository.state.config_states).to eq(expected_config_states)
          end
        end

        context 'update' do
          it 'return config_states' do
            repository.transaction do |_repository, transaction|
              transaction.insert(path, target, content)
            end

            expect(repository.state.config_states).to eq(expected_config_states)

            repository.transaction do |_repository, transaction|
              transaction.update(path, new_target, new_content)
            end

            expected_updated_config_states = [
              { id: path.config_id, product: path.product, version: 2, apply_error: nil, apply_state: 1 }
            ]

            expect(repository.state.config_states).to_not eq(expected_config_states)
            expect(repository.state.config_states).to eq(expected_updated_config_states)
          end
        end

        context 'delete' do
          it 'return config_states' do
            repository.transaction do |_repository, transaction|
              transaction.insert(path, target, content)
            end

            expect(repository.state.config_states).to eq(expected_config_states)

            repository.transaction do |_repository, transaction|
              transaction.delete(path)
            end

            expect(repository.state.config_states).to eq([])
          end
        end
      end
    end
  end
end
