require 'helper'
require 'ddtrace'
require 'graphql'
require_relative 'test_types'

module Datadog
  module Contrib
    module GraphQL
      class TracerTest < Minitest::Test
        def setup
          @tracer = get_test_tracer
          @schema = build_schema

          Datadog.configure do |c|
            c.use :graphql,
                  service_name: 'graphql-test',
                  tracer: tracer,
                  schemas: [schema]
          end
        end

        def test_trace
          # Perform query
          query = '{ foo(id: 1) { name } }'
          result = schema.execute(query, variables: {}, context: {}, operation_name: nil)

          # Expect no errors
          assert_nil(result.to_h['errors'])

          # Expect nine spans
          assert_equal(9, all_spans.length)

          # Expect each span to be properly named
          all_spans.each do |span|
            assert_equal('graphql-test', span.service)
            assert_equal(true, !span.resource.to_s.empty?)
          end
        end

        def build_schema
          ::GraphQL::Schema.define do
            query(QueryType)
          end
        end

        private

        attr_reader :tracer, :schema

        def all_spans
          tracer.writer.spans(:keep)
        end
      end
    end
  end
end
