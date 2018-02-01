require 'spec_helper'
require 'ddtrace/contrib/graphql/test_types'

require 'ddtrace'

# rubocop:disable Metrics/BlockLength
RSpec.describe 'GraphQL patcher' do
  include_context 'GraphQL test schema'

  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }

  def all_spans
    tracer.writer.spans(:keep)
  end

  before(:each) do
    Datadog.configure do |c|
      c.use :graphql,
            service_name: 'graphql-test',
            tracer: tracer,
            schemas: [schema]
    end
  end

  describe 'query trace' do
    subject(:result) { schema.execute(query, variables: {}, context: {}, operation_name: nil) }

    let(:query) { '{ foo(id: 1) { name } }' }
    let(:variables) { {} }
    let(:context) { {} }
    let(:operation_name) { nil }

    it do
      # Expect no errors
      expect(result.to_h['errors']).to be nil

      # Expect nine spans
      expect(all_spans).to have(9).items

      # Expect each span to be properly named
      all_spans.each do |span|
        expect(span.service).to eq('graphql-test')
        expect(span.resource.to_s).to_not be_empty
      end
    end
  end
end
