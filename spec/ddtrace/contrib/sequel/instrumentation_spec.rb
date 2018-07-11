require 'spec_helper'

require 'time'
require 'sequel'
require 'ddtrace'
require 'ddtrace/contrib/sequel/integration'

RSpec.describe 'Sequel instrumentation' do
  let(:tracer) { Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:configuration_options) { { tracer: tracer } }
  let(:sequel) do
    Sequel.sqlite(':memory:').tap do |s|
      Datadog.configure(s, tracer: tracer)
    end
  end

  let(:spans) { tracer.writer.spans }

  before(:each) do
    skip('Sequel not compatible.') unless Datadog::Contrib::Sequel::Integration.compatible?

    # Reset options (that might linger from other tests)
    Datadog.configuration[:sequel].reset_options!

    # Patch Sequel
    Datadog.configure do |c|
      c.use :sequel, configuration_options
    end
  end

  describe 'for a SQLite database' do
    before(:each) do
      sequel.create_table(:table) do
        String :name
      end
    end

    describe 'when queried through a Sequel::Database object' do
      before(:each) { sequel.run(query) }
      let(:query) { 'SELECT * FROM \'table\' WHERE `name` = \'John Doe\'' }
      let(:span) { spans.first }

      it 'traces the command' do
        expect(span.name).to eq('sequel.query')
        # Expect it to be the normalized adapter name.
        expect(span.service).to eq('sqlite')
        expect(span.span_type).to eq('sql')
        expect(span.get_tag('sequel.db.vendor')).to eq('sqlite')
        # Expect non-quantized query: agent does SQL quantization.
        expect(span.resource).to eq(query)
        expect(span.status).to eq(0)
        expect(span.parent_id).to eq(0)
      end
    end

    describe 'when queried through a Sequel::Dataset' do
      let(:process_span) { spans[0] }
      let(:publish_span) { spans[1] }
      let(:sequel_cmd1_span) { spans[2] }
      let(:sequel_cmd2_span) { spans[3] }
      let(:sequel_cmd3_span) { spans[4] }
      let(:sequel_cmd4_span) { spans[5] }

      before(:each) do
        tracer.trace('publish') do |span|
          span.service = 'webapp'
          span.resource = '/index'
          tracer.trace('process') do |subspan|
            subspan.service = 'datalayer'
            subspan.resource = 'home'
            sequel[:table].insert(name: 'data1')
            sequel[:table].insert(name: 'data2')
            data = sequel[:table].select.to_a
            expect(data.length).to eq(2)
            data.each do |row|
              expect(row[:name]).to match(/^data.$/)
            end
          end
        end
      end

      it do
        expect(spans).to have(6).items

        # Check publish span
        expect(publish_span.name).to eq('publish')
        expect(publish_span.service).to eq('webapp')
        expect(publish_span.resource).to eq('/index')
        expect(publish_span.span_id).to_not eq(publish_span.trace_id)
        expect(publish_span.parent_id).to eq(0)

        # Check process span
        expect(process_span.name).to eq('process')
        expect(process_span.service).to eq('datalayer')
        expect(process_span.resource).to eq('home')
        expect(process_span.parent_id).to eq(publish_span.span_id)
        expect(process_span.trace_id).to eq(publish_span.trace_id)

        # Check each command span
        [
          [sequel_cmd1_span, 'INSERT INTO `table` (`name`) VALUES (\'data1\')'],
          [sequel_cmd2_span, 'INSERT INTO `table` (`name`) VALUES (\'data2\')'],
          [sequel_cmd3_span, 'SELECT * FROM `table`'],
          [sequel_cmd4_span, 'SELECT sqlite_version()']
        ].each do |command_span, query|
          expect(command_span.name).to eq('sequel.query')
          # Expect it to be the normalized adapter name.
          expect(command_span.service).to eq('sqlite')
          expect(command_span.span_type).to eq('sql')
          expect(command_span.get_tag('sequel.db.vendor')).to eq('sqlite')
          # Expect non-quantized query: agent does SQL quantization.
          expect(command_span.resource).to eq(query)
          expect(command_span.status).to eq(0)
          expect(command_span.parent_id).to eq(process_span.span_id)
          expect(command_span.trace_id).to eq(publish_span.trace_id)
        end
      end
    end
  end
end
