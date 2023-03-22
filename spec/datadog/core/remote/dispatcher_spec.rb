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
