# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/configuration/repository'
require 'datadog/core/remote/configuration/target'

RSpec.describe Datadog::Core::Remote::Configuration::Repository do
  subject(:repository) { described_class.new }
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

  let(:content) do
    Datadog::Core::Remote::Configuration::Content.parse({ :path => path.to_s, :content => string_io_content })
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
          { :path => path.to_s,
            :content => StringIO.new('hello world') }
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
          { :path => new_path.to_s,
            :content => StringIO.new('hello world') }
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
end
