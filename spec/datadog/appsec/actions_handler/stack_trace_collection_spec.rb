# frozen_string_literal: true

require 'datadog/appsec/actions_handler/stack_trace_collection'
require 'support/thread_backtrace_helpers'

RSpec.describe Datadog::AppSec::ActionsHandler::StackTraceCollection do
  describe '.collect' do
    # "/app/spec/support/thread_backtrace_helpers.rb:12:in `block in locations_inside_nested_blocks'",
    # "/app/spec/support/thread_backtrace_helpers.rb:14:in `block (2 levels) in locations_inside_nested_blocks'",
    # "/app/spec/support/thread_backtrace_helpers.rb:16:in `block (3 levels) in locations_inside_nested_blocks'",
    # "/app/spec/support/thread_backtrace_helpers.rb:16:in `block (4 levels) in locations_inside_nested_blocks'",
    # "/app/spec/support/thread_backtrace_helpers.rb:16:in `block (5 levels) in locations_inside_nested_blocks'",
    # "/app/lib/datadog/appsec/actions_handler/stack_trace_collection.rb:12:in `block in locations_inside_nested_blocks"
    let(:frames) { ThreadBacktraceHelper.locations_inside_nested_blocks_with_datadog_frame }

    before do
      allow(described_class).to receive(:filter_map_datadog_locations).and_return(
        described_class.filter_map_datadog_locations(frames)
      )
    end

    context 'with values larger than stack trace' do
      subject(:collection) { described_class.collect(max_depth: 10, top_percent: 75) }

      it 'returns stack frames excluding those from datadog' do
        expect(collection.any? { |loc| loc[:text].include?('lib/datadog') }).to be false
      end

      it 'returns the correct number of stack frames' do
        expect(collection.size).to eq(5)
      end
    end

    context 'with max_depth set to 4' do
      subject(:collection) { described_class.collect(max_depth: 4, top_percent: 75) }

      it 'creates a stack trace with 4 frames, 3 top' do
        expect(collection.count).to eq(4)
        expect(collection[2][:text]).to eq(frames[2].to_s)
        expect(collection[3][:text]).to eq(frames[4].to_s)
      end

      context 'with max_depth_top_percent set to 25' do
        subject(:collection) { described_class.collect(max_depth: 4, top_percent: 25) }

        it 'creates a stack trace with 4 frames, 1 top' do
          expect(collection.count).to eq(4)
          expect(collection[0][:text]).to eq(frames[0].to_s)
          expect(collection[1][:text]).to eq(frames[2].to_s)
        end
      end

      context 'with max_depth_top_percent set to 100' do
        subject(:collection) { described_class.collect(max_depth: 4, top_percent: 100) }

        it 'creates a stack trace with 4 top frames' do
          expect(collection.count).to eq(4)
          expect(collection[0][:text]).to eq(frames[0].to_s)
          expect(collection[3][:text]).to eq(frames[3].to_s)
        end
      end

      context 'with max_depth_top_percent set to 0' do
        subject(:collection) { described_class.collect(max_depth: 4, top_percent: 0) }

        it 'creates a stack trace with 4 bottom frames' do
          expect(collection.count).to eq(4)
          expect(collection[0][:text]).to eq(frames[1].to_s)
          expect(collection[3][:text]).to eq(frames[4].to_s)
        end
      end
    end

    context 'with max_depth set to 3 and max_depth_top_percent set to 66.67' do
      subject(:collection) { described_class.collect(max_depth: 3, top_percent: 200 / 3.0) }

      it 'creates a stack trace with 3 frames, 2 top' do
        expect(collection.count).to eq(3)
        expect(collection[1][:text]).to eq(frames[1].to_s)
        expect(collection[2][:text]).to eq(frames[4].to_s)
      end
    end
  end
end
