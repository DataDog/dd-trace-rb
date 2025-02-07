# frozen_string_literal: true

require 'ostruct'

require 'datadog/appsec/actions_handler/stack_trace/collector'
require 'datadog/appsec/actions_handler/stack_trace/frame'
require 'datadog/appsec/ext'
require 'datadog/appsec/spec_helper'
require 'support/thread_backtrace_helpers'

RSpec.describe Datadog::AppSec::ActionsHandler::StackTrace::Collector do
  describe '.collect' do
    subject(:collection) { described_class.collect(frames) }

    let(:max_depth) { nil }
    let(:max_depth_top_percent) { nil }

    # "/app/spec/support/thread_backtrace_helpers.rb:12:in `block in locations_inside_nested_blocks'",
    # "/app/spec/support/thread_backtrace_helpers.rb:14:in `block (2 levels) in locations_inside_nested_blocks'",
    # "/app/spec/support/thread_backtrace_helpers.rb:16:in `block (3 levels) in locations_inside_nested_blocks'",
    # "/app/spec/support/thread_backtrace_helpers.rb:16:in `block (4 levels) in locations_inside_nested_blocks'",
    # "/app/spec/support/thread_backtrace_helpers.rb:16:in `block (5 levels) in locations_inside_nested_blocks'"
    let(:frames) { ThreadBacktraceHelper.locations_inside_nested_blocks }

    before do
      Datadog.configure do |c|
        c.appsec.stack_trace.max_depth = max_depth if max_depth
        c.appsec.stack_trace.max_depth_top_percent = max_depth_top_percent if max_depth_top_percent
      end
    end

    context 'with default values' do
      it 'creates a stack trace with default values' do
        expect(collection.count).to eq(5)
      end
    end

    context 'without values' do
      let(:frames) { nil }

      it 'returns an empty array' do
        expect(collection).to eq([])
      end
    end

    context 'with max_depth set to 4' do
      let(:max_depth) { 4 }

      it 'creates a stack trace with 4 frames, 3 top' do
        expect(collection.count).to eq(4)
        expect(collection[2].text).to eq(frames[2].to_s)
        expect(collection[3].text).to eq(frames[4].to_s)
      end

      context 'with max_depth_top_percent set to 25' do
        let(:max_depth_top_percent) { 25 }

        it 'creates a stack trace with 4 frames, 1 top' do
          expect(collection.count).to eq(4)
          expect(collection[0].text).to eq(frames[0].to_s)
          expect(collection[1].text).to eq(frames[2].to_s)
        end
      end

      context 'with max_depth_top_percent set to 100' do
        let(:max_depth_top_percent) { 100 }

        it 'creates a stack trace with 4 top frames' do
          expect(collection.count).to eq(4)
          expect(collection[0].text).to eq(frames[0].to_s)
          expect(collection[3].text).to eq(frames[3].to_s)
        end
      end

      context 'with max_depth_top_percent set to 0' do
        let(:max_depth_top_percent) { 0 }

        it 'creates a stack trace with 4 bottom frames' do
          expect(collection.count).to eq(4)
          expect(collection[0].text).to eq(frames[1].to_s)
          expect(collection[3].text).to eq(frames[4].to_s)
        end
      end
    end

    context 'with max_depth set to 3' do
      let(:max_depth) { 3 }

      context 'with max_depth_top_percent set to 66.67' do
        let(:max_depth_top_percent) { 200 / 3.0 }

        it 'creates a stack trace with 3 frames, 2 top' do
          expect(collection.count).to eq(3)
          expect(collection[1].text).to eq(frames[1].to_s)
          expect(collection[2].text).to eq(frames[4].to_s)
        end
      end
    end

    context 'with max_depth set to 0' do
      let(:max_depth) { 0 }
      let(:frames) { ThreadBacktraceHelper.thousand_locations }

      it 'does not apply any limit' do
        expect(collection.count).to eq(1000)
      end
    end

    context 'with values encoded in ASCII-8BIT' do
      let(:frames) { ThreadBacktraceHelper.location_ascii_8bit }

      it 'creates a stack trace with correctly encoded values' do
        expect(collection.count).to eq(1)
        expect(collection[0].id).to eq(0)
        expect(collection[0].text).to eq(frames[0].to_s)
        expect(collection[0].text.encoding).to eq(Encoding::UTF_8)
        expect(collection[0].file).to eq(frames[0].path)
        expect(collection[0].file.encoding).to eq(Encoding::UTF_8)
        expect(collection[0].line).to eq(frames[0].lineno)
        expect(collection[0].function).to eq(frames[0].label)
        expect(collection[0].function.encoding).to eq(Encoding::UTF_8)
      end
    end
  end
end
