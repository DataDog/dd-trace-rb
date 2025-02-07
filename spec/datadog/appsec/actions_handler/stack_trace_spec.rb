# frozen_string_literal: true

require 'ostruct'

require 'datadog/appsec/actions_handler/stack_trace/frame'
require 'datadog/appsec/actions_handler/stack_trace/representor'

require 'datadog/appsec/actions_handler/stack_trace'
require 'datadog/appsec/ext'
require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::ActionsHandler::StackTrace do
  describe '.skip_stack_trace?' do
    subject(:skip_stack_trace?) { described_class.skip_stack_trace?(context, group: group) }

    let(:trace_op) { Datadog::Tracing::TraceOperation.new }
    let(:span_op) { Datadog::Tracing::SpanOperation.new('span_test') }
    let(:context) { OpenStruct.new(trace: trace_op, span: span_op) }
    let(:group) { Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY }
    let(:max_collect) { 0 }

    before do
      allow(Datadog.configuration.appsec.stack_trace).to receive(:max_collect).and_return(max_collect)
    end

    context 'when max_collect is 0' do
      it { is_expected.to be false }
    end

    context 'when max_collect is 2' do
      let(:max_collect) { 2 }

      context 'with no stack traces' do
        it { is_expected.to be false }
      end

      context 'with one element contained in same group in trace' do
        before do
          trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE] = { group => [1] }
        end

        it { is_expected.to be false }
      end

      context 'with one element contained in same group in span' do
        before do
          span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE] = { group => [1] }
        end

        it { is_expected.to be false }
      end

      context 'with two elements contained in same group in trace' do
        before do
          trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE] = { group => [1, 2] }
        end

        it { is_expected.to be true }
      end

      context 'with two elements contained in same group in span' do
        before do
          span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE] = { group => [1, 2] }
        end

        it { is_expected.to be true }
      end

      context 'with one element contained in same group in span and trace' do
        before do
          trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE] = { group => [1] }
          span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE] = { group => [2] }
        end

        it { is_expected.to be true }
      end

      context 'with two elements contained in different group in trace' do
        before do
          trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE] = { 'other_group' => [1, 2] }
        end

        it { is_expected.to be false }
      end
    end

    context 'when both trace and span are nil' do
      let(:trace_op) { nil }
      let(:span_op) { nil }

      it { is_expected.to be true }
    end
  end

  describe '.collect_stack_frames' do
    subject(:collect_stack_frames) { described_class.collect_stack_frames }

    it 'returns stack frames excluding those from datadog' do
      expect(collect_stack_frames.any? { |loc| loc.file.include?('lib/datadog') }).to be false
    end
  end

  describe '.add_stack_trace_to_context' do
    let(:stack_trace) do
      Datadog::AppSec::ActionsHandler::StackTrace::Representor.new(
        id: 'foo',
        message: 'bar',
        frames: [
          Datadog::AppSec::ActionsHandler::StackTrace::Frame.new(
            id: 1,
            text: 'frame 1',
            file: 'file 1',
            line: 1,
            function: 'function 1'
          ),
          Datadog::AppSec::ActionsHandler::StackTrace::Frame.new(
            id: 2,
            text: 'frame 2',
            file: 'file 2',
            line: 2,
            function: 'function 2'
          )
        ]
      )
    end
    let(:trace_op) { Datadog::Tracing::TraceOperation.new }
    let(:span_op) { Datadog::Tracing::SpanOperation.new('span_test') }
    let(:context) { OpenStruct.new(trace: trace_op, span: span_op) }
    let(:group) { Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY }

    context 'without existing dd.stack, with trace and span in context' do
      it 'adds stack trace to trace' do
        described_class.add_stack_trace_to_context(stack_trace, context, group: group)

        expect(trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].size).to eq(1)
        expect(trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].first.id).to eq('foo')
        expect(trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].first.message).to eq('bar')
        expect(trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].first.frames.size).to eq(2)
      end
    end

    context 'with existing dd.stack, with trace and span in context' do
      before do
        trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE] = { group => [1] }
      end

      it 'adds stack trace to trace' do
        described_class.add_stack_trace_to_context(stack_trace, context, group: group)

        expect(trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].size).to eq(2)
        expect(trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group][1].id).to eq('foo')
        expect(trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group][1].message).to eq('bar')
        expect(trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group][1].frames.size).to eq(2)
      end
    end

    context 'without existing dd.stack, with only span in context' do
      let(:context) { OpenStruct.new(span: span_op) }

      it 'adds stack trace to span' do
        described_class.add_stack_trace_to_context(stack_trace, context, group: group)

        expect(span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].size).to eq(1)
        expect(span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].first.id).to eq('foo')
        expect(span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].first.message).to eq('bar')
        expect(span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].first.frames.size).to eq(2)
      end
    end

    context 'with existing dd.stack, with only span in context' do
      let(:context) { OpenStruct.new(span: span_op) }

      before do
        span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE] = { group => [1] }
      end

      it 'adds stack trace to span' do
        described_class.add_stack_trace_to_context(stack_trace, context, group: group)

        expect(span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group].size).to eq(2)
        expect(span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group][1].id).to eq('foo')
        expect(span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group][1].message).to eq('bar')
        expect(span_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE][group][1].frames.size).to eq(2)
      end
    end
  end
end
