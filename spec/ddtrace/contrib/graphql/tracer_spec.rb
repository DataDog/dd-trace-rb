# typed: ignore
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/graphql/test_types'

require 'ddtrace'
RSpec.describe 'GraphQL patcher' do
  include ConfigurationHelpers

  # GraphQL generates tons of warnings.
  # This suppresses those warnings.
  around do |example|
    without_warnings do
      example.run
    end
  end

  let(:root_span) { spans.find { |s| s.parent.nil? } }

  RSpec.shared_examples 'Schema patcher' do
    before do
      remove_patch!(:graphql)
      Datadog.configure do |c|
        c.use :graphql,
              service_name: 'graphql-test',
              schemas: [schema]
      end
    end

    describe 'execution strategy' do
      xit 'matches expected strategy' do
        expect(schema.query_execution_strategy).to eq(expected_execution_strategy)
      end
    end

    describe 'query trace' do
      subject(:result) { schema.execute(query, variables: variables{}, context: context, operation_name: operation_name) }

      before { result }

      context 'anonymous query' do
        # let(:query) { 'query testQuery{ foo(id: 1) { name } }' }
        let(:query) { "{ foo(id: 1) { name } }" }

        it do
          print_trace(spans)

          expect(result.to_h['errors']).to be nil
          expect(result['data']['foo']['name']).to eq('expensive string')
          expect(root_span.resource).to eq('{ foo(id: ?) { name } }')
          # puts a
        end

        xit 'removes inline values' do
          expect(root_span.resource).to eq('{ foo(id: ?) { name } }')
        end
      end

      context 'with fragment' do
        # TODO: test with fragment, for testing the parser if needed
        #
        # "{ foo(id: 1) { ...fooFields } }
        #
        # fragment fooFields on Foo {
        #   name
        # }"
      end

      let(:query) { '{ foo(id: 1) { name } }' }
      let(:variables) { {} }
      let(:context) { {} }
      let(:operation_name) { nil }

      xit do
        # Expect no errors
        expect(result.to_h['errors']).to be nil

        # List of valid resource names
        # (If this is too brittle, revist later.)
        valid_resource_names = [
          'Query.foo',
          'analyze.graphql',
          'execute.graphql',
          'lex.graphql',
          'parse.graphql',
          'validate.graphql'
        ]

        print_trace(spans)

        # Legacy execution strategy
        # {GraphQL::Execution::Execute}
        # does not execute authorization code.
        if schema.query_execution_strategy == GraphQL::Execution::Execute
          expect(spans).to have(9).items
        else
          valid_resource_names += [
            'Foo.authorized',
            'Query.authorized'
          ]

          expect(spans).to have(11).items
        end

        # Expect root span to be 'execute.graphql'
        expect(root_span.name).to eq('execute.graphql')
        expect(root_span.resource).to eq('execute.graphql')

        # TODO: Assert GraphQL root span sets analytics sample rate.
        #       Need to wait on pull request to be merged and GraphQL released.
        #       See https://github.com/rmosolgo/graphql-ruby/pull/2154

        # Expect each span to be properly named
        spans.each do |span|
          expect(span.service).to eq('graphql-test')
          expect(valid_resource_names).to include(span.resource)
        end
      end
    end
  end

  context 'class-based schema' do
    include_context 'GraphQL class-based schema'
    # Newer execution strategy (default since 1.12.0)
    let(:expected_execution_strategy) { GraphQL::Execution::Interpreter }

    it_behaves_like 'Schema patcher'
  end

  xdescribe '.define-style schema' do
    include_context 'GraphQL .define-style schema'
    # Legacy execution strategy (default before 1.12.0)
    let(:expected_execution_strategy) { GraphQL::Execution::Execute }

    it_behaves_like 'Schema patcher'
  end
end



def print_active_spans(context = ::Datadog.tracer.call_context, *roots)
  print_trace(context.instance_variable_get(:@trace), *roots)
end

def print_trace(spans, *roots)
  roots = spans.select { |s| !s.parent } if roots.empty?

  return STDERR.puts "No root!" if roots.empty?

  roots.map { |root| print_with_root(spans, root) }
end

def print_with_root(spans, root)
  start_time = root.start_time
  end_time = root.end_time

  # print_span(start_time, end_time, root)


  spans.sort_by(&:start_time).each do |span|
    print_span(start_time, end_time, span)
  end

  # parent = root
  # while (span = parent = next_span(spans, parent))
  #   print_span(start_time, end_time, span)
  # end
end

def next_span(spans, parent)
  spans.find { |s| s.parent_id == parent.span_id }
end

def print_span(start_time, end_time, span)
  unless end_time # Unfinished spans
    unfinished = true
    end_time = Time.now
  end

  size = 100
  total_time = (end_time - start_time).to_f

  prefix = ' ' * ((span.start_time.to_f - start_time.to_f) / total_time * size).to_i
  print prefix

  label = "#{span.name}:#{span.resource}(#{short_id(span.span_id)},↑#{short_id(span.parent_id)})"
  print label

  suffix = '─' * [size - ((end_time.to_f - span.end_time.to_f) / total_time * size) - prefix.size - label.size, 0].max
  print suffix

  puts
end

def short_id(id)
  (id % 1000000).to_s(36)
end

class Datadog::Span
  def short_id
    Kernel.send(:short_id, span_id)
  end
end
