# frozen_string_literal: true

require 'datadog/appsec/actions_handler/stack_trace_in_metastruct'
require 'datadog/tracing/metadata/metastruct'

RSpec.describe Datadog::AppSec::ActionsHandler::StackTraceInMetastruct do
  subject(:stack_trace_in_metastruct) { described_class.create(metastruct) }
  let(:metastruct) { Datadog::Tracing::Metadata::Metastruct.new(metastruct_hash) }
  let(:metastruct_hash) { {} }

  describe '.count' do
    subject(:count) { stack_trace_in_metastruct.count }

    context 'with nil as metastruct' do
      let(:metastruct) { nil }

      it { is_expected.to eq 0 }
    end

    context 'with empty metastruct' do
      it { is_expected.to eq 0 }
    end

    context 'with metastruct containing non-exploit stack traces' do
      let(:metastruct_hash) do
        {
          '_dd.stack' => {
            'vulnerabilities' => [1, 2]
          }
        }
      end

      it { is_expected.to eq 0 }
    end

    context 'with metastruct containing exploit stack traces' do
      let(:metastruct_hash) do
        {
          '_dd.stack' => {
            'exploit' => [1, 2]
          }
        }
      end

      it { is_expected.to eq 2 }
    end
  end

  describe '.push' do
    before do
      stack_trace_in_metastruct.push({ language: 'ruby', stack_id: 'foo', frames: [] })
    end

    context 'with empty metastruct' do
      it 'adds a new stack trace to the metastruct' do
        expect(metastruct.to_h).to eq(
          '_dd.stack' => {
            'exploit' => [
              {
                language: 'ruby',
                stack_id: 'foo',
                frames: []
              }
            ]
          }
        )
      end
    end

    context 'with existing exploit stack traces in different group' do
      let(:metastruct_hash) do
        {
          '_dd.stack' => {
            'vulnerabilities' => [1, 2]
          }
        }
      end

      it 'adds a new stack trace to the metastruct' do
        expect(metastruct.to_h).to eq(
          '_dd.stack' => {
            'vulnerabilities' => [1, 2],
            'exploit' => [
              {
                language: 'ruby',
                stack_id: 'foo',
                frames: []
              }
            ]
          }
        )
      end
    end

    context 'with existing exploit stack traces in the same group' do
      let(:metastruct_hash) do
        {
          '_dd.stack' => {
            'exploit' => [1, 2]
          }
        }
      end

      it 'adds a new stack trace to the metastruct' do
        expect(metastruct.to_h).to eq(
          '_dd.stack' => {
            'exploit' => [
              1,
              2,
              {
                language: 'ruby',
                stack_id: 'foo',
                frames: []
              }
            ]
          }
        )
      end
    end
  end
end
