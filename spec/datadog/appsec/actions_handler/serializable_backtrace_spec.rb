# frozen_string_literal: true

require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::ActionsHandler::SerializableBacktrace do
  let(:location_struct) do
    Struct.new(:path, :lineno, :label) do
      def to_s
        "#{path}:#{lineno}:in `#{label}'"
      end
    end
  end

  describe '#to_msgpack' do
    before do
      Datadog.configuration.appsec.stack_trace.max_depth = 40
      Datadog.configuration.appsec.stack_trace.top_percentage = 75
    end

    after do
      Datadog.configuration.appsec.reset!
    end

    it 'correctly serializes stack attributes' do
      result = pack_and_unpack(described_class.new(locations: [], stack_id: 1))

      expect(result.fetch('stack_id')).to eq(1)
      expect(result.fetch('language')).to eq('ruby')
    end

    it 'correctly serializes stack frames' do
      location = location_struct.new('path/to/file.rb', 15, 'SomeModule::SomeClass#some_method')

      result = pack_and_unpack(described_class.new(locations: [location], stack_id: 1))
      frames = result.fetch('frames')

      expect(frames.size).to eq(1)

      aggregate_failures('frame attributes') do
        expect(frames[0].fetch('id')).to eq(0)
        expect(frames[0].fetch('text')).to eq('path/to/file.rb:15:in `SomeModule::SomeClass#some_method\'')
        expect(frames[0].fetch('file')).to eq('path/to/file.rb')
        expect(frames[0].fetch('line')).to eq(15)
        expect(frames[0].fetch('class_name')).to eq('SomeModule::SomeClass')
        expect(frames[0].fetch('function')).to eq('some_method')
      end
    end

    it 'drops datadog library frames and does not increase frame id for them' do
      location_1 = location_struct.new('path/to/file.rb', 20, 'SomeModule.some_method')
      location_2 = location_struct.new('lib/datadog/file.rb', 25, 'Datadog::SomeClass.some_method')
      location_3 = location_struct.new('path/to/another/file.rb', 30, 'AnotherModule.another_method')

      result = pack_and_unpack(described_class.new(locations: [location_1, location_2, location_3], stack_id: 1))
      frames = result.fetch('frames')

      expect(frames.size).to eq(2)

      expect(frames[0].fetch('id')).to eq(0)
      expect(frames[0].fetch('file')).to eq('path/to/file.rb')

      expect(frames[1].fetch('id')).to eq(1)
      expect(frames[1].fetch('file')).to eq('path/to/another/file.rb')
    end

    it 'drops frames from the middle of a big stack but keeps original frame ids' do
      locations = 0.upto(49).map do |i|
        location_struct.new("path/to/file_#{i}.rb", 10, "SomeModule::SomeClass#some_method_#{i}")
      end

      result = pack_and_unpack(described_class.new(locations: locations, stack_id: 1))
      frames = result.fetch('frames')

      expect(frames.size).to eq(40)

      aggregate_failures('top frames') do
        0.upto(29) do |i|
          expect(frames[i].fetch('id')).to eq(i)
          expect(frames[i].fetch('file')).to eq(locations[i].path)
        end
      end

      aggregate_failures('bottom frames') do
        1.upto(10) do |i|
          expect(frames[-i].fetch('id')).to eq(50 - i)
          expect(frames[-i].fetch('file')).to eq(locations[50 - i].path)
        end
      end
    end

    context 'class and function name parsing' do
      it 'parses labels with plain function names' do
        location = location_struct.new('path/to/file.rb', 15, 'some_method')

        result = pack_and_unpack(described_class.new(locations: [location], stack_id: 1))
        frame = result.fetch('frames')[0]

        aggregate_failures('frame attributes') do
          expect(frame.fetch('class_name')).to be_nil
          expect(frame.fetch('function')).to eq('some_method')
        end
      end

      it 'parses instance function names' do
        location = location_struct.new('path/to/file.rb', 15, 'SomeClass#some_method')

        result = pack_and_unpack(described_class.new(locations: [location], stack_id: 1))
        frame = result.fetch('frames')[0]

        aggregate_failures('frame attributes') do
          expect(frame.fetch('class_name')).to eq('SomeClass')
          expect(frame.fetch('function')).to eq('some_method')
        end
      end

      it 'parses class function names' do
        location = location_struct.new('path/to/file.rb', 15, 'SomeClass.some_class_method')

        result = pack_and_unpack(described_class.new(locations: [location], stack_id: 1))
        frame = result.fetch('frames')[0]

        aggregate_failures('frame attributes') do
          expect(frame.fetch('class_name')).to eq('SomeClass')
          expect(frame.fetch('function')).to eq('some_class_method')
        end
      end

      it 'parses namespaced class names' do
        location = location_struct.new('path/to/file.rb', 15, 'SomeModule::SomeClass#some_method')

        result = pack_and_unpack(described_class.new(locations: [location], stack_id: 1))
        frame = result.fetch('frames')[0]

        aggregate_failures('frame attributes') do
          expect(frame.fetch('class_name')).to eq('SomeModule::SomeClass')
          expect(frame.fetch('function')).to eq('some_method')
        end
      end

      it 'ignores block labels' do
        location_one = location_struct.new('path/to/file.rb', 15, 'block in some_method')
        location_two = location_struct.new('path/to/file.rb', 15, 'block (2 levels) in SomeClass.some_method')

        result = pack_and_unpack(described_class.new(locations: [location_one, location_two], stack_id: 1))
        frames = result.fetch('frames')

        aggregate_failures('for first level blocks') do
          expect(frames[0].fetch('class_name')).to be_nil
          expect(frames[0].fetch('function')).to eq('some_method')
        end

        aggregate_failures('for n level blocks') do
          expect(frames[1].fetch('class_name')).to eq('SomeClass')
          expect(frames[1].fetch('function')).to eq('some_method')
        end
      end

      it 'parses labels for top scope' do
        location = location_struct.new('path/to/file.rb', 15, 'block (3 levels) in <top (required)>')

        result = pack_and_unpack(described_class.new(locations: [location], stack_id: 1))
        frame = result.fetch('frames')[0]

        aggregate_failures('frame attributes') do
          expect(frame.fetch('class_name')).to be_nil
          expect(frame.fetch('function')).to be_nil
        end
      end
    end
  end

  def pack_and_unpack(serializable_backtrace)
    serialized_result = MessagePack.pack(serializable_backtrace)
    MessagePack.unpack(serialized_result)
  end
end
