# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "ostruct" # graphql 1.13 uses OpenStruct without requiring ostruct itself
require "graphql"

RSpec.describe "Datadog::Tracing::Contrib::GraphQL::UnifiedTrace" do
  before do
    skip "UnifiedTrace is only supported in GraphQL 2.0.19 and above" if Gem::Version.new(::GraphQL::VERSION) < Gem::Version.new("2.0.19")
    require "datadog/tracing/contrib/graphql/unified_trace"
  end

  let(:described_class) { Datadog::Tracing::Contrib::GraphQL::UnifiedTrace }

  describe "span selection" do
    subject(:result) { schema.execute(query, root_value: root_value) }

    let(:query) { "{ item { value } }" }
    let(:root_value) { {item: {value: field_value}} }
    let(:resolved_value) { "EXAMPLE" }
    let(:field_value) { lazy_field ? ::GraphQL::Execution::Lazy.new { resolved_value } : resolved_value }
    let(:value_type) { ::GraphQL::Types::String }
    let(:field_type) { value_type }
    let(:field_options) { {} }
    let(:trace_options) { {} }
    let(:lazy_field) { false }
    let(:lazy_authorization) { false }
    let(:authorization_result) { true }
    let(:lazy_type_resolution) { false }
    let(:item_return_type) { item_type }

    let(:enum_type) do
      stub_const("SpanSelectionEnum", Class.new(::GraphQL::Schema::Enum) do
        value "EXAMPLE"
      end)
    end

    let(:item_type) do
      type = field_type
      options = field_options
      item = stub_const("SpanSelectionItem", Class.new(::GraphQL::Schema::Object) do
        field :value, type, null: false, **options
      end)

      allowed = authorization_result
      lazy = lazy_authorization
      item.define_singleton_method(:authorized?) do |_object, _context|
        lazy ? ::GraphQL::Execution::Lazy.new { allowed } : allowed
      end

      item
    end

    let(:query_type) do
      type = item_return_type
      stub_const("SpanSelectionQuery", Class.new(::GraphQL::Schema::Object) do
        field :item, type, null: false
      end)
    end

    let(:schema) do
      root_type = query_type
      trace_module = described_class
      options = trace_options
      stub_const("SpanSelectionSchema", Class.new(::GraphQL::Schema) do
        query root_type
        trace_with trace_module, **options
      end)
    end

    def span_names_for_resource(resource)
      spans.select { |span| span.resource == resource }.map(&:name)
    end

    def span_name_resource_pairs(*names)
      spans.select { |span| names.include?(span.name) }.map { |span| [span.name, span.resource] }
    end

    shared_examples "leaf field span selection" do
      [
        {description: "default options", trace_options: {}, field_options: {}, traced: false},
        {description: "trace_scalars: false", trace_options: {trace_scalars: false}, field_options: {}, traced: false},
        {description: "trace_scalars: true", trace_options: {trace_scalars: true}, field_options: {}, traced: true},
        {
          description: "trace: true overriding trace_scalars: false",
          trace_options: {trace_scalars: false},
          field_options: {trace: true},
          traced: true,
        },
        {
          description: "trace: false overriding trace_scalars: true",
          trace_options: {trace_scalars: true},
          field_options: {trace: false},
          traced: false,
        },
      ].each do |row|
        context "with #{row[:description]}" do
          let(:trace_options) { row[:trace_options] }
          let(:field_options) { row[:field_options] }

          it "#{row[:traced] ? "creates" : "skips"} the leaf field's resolver spans" do
            expect(result.to_h).to eq("data" => {"item" => {"value" => resolved_value}})

            expected_names = if !row[:traced]
              []
            elsif lazy_field
              ["graphql.resolve", "graphql.resolve_lazy"]
            else
              ["graphql.resolve"]
            end

            expect(span_names_for_resource("SpanSelectionItem.value")).to match_array(expected_names)
          end

          it "keeps the object field's resolver span" do
            expect(result.to_h).to eq("data" => {"item" => {"value" => resolved_value}})

            expect(span_names_for_resource("SpanSelectionQuery.item")).to eq(["graphql.resolve"])
          end
        end
      end
    end

    [false, true].each do |lazy|
      context "with #{lazy ? "lazy" : "synchronous"} field resolution" do
        let(:lazy_field) { lazy }

        context "with a scalar field" do
          include_examples "leaf field span selection"
        end

        context "with an enum field" do
          let(:value_type) { enum_type }

          include_examples "leaf field span selection"
        end

        context "with a scalar list field" do
          let(:field_type) { [value_type] }
          let(:resolved_value) { ["EXAMPLE"] }

          include_examples "leaf field span selection"
        end

        context "with an enum list field" do
          let(:value_type) { enum_type }
          let(:field_type) { [value_type] }
          let(:resolved_value) { ["EXAMPLE"] }

          include_examples "leaf field span selection"
        end
      end
    end

    describe "authorization spans" do
      [false, true].each do |lazy|
        context "with #{lazy ? "lazy" : "synchronous"} authorization" do
          let(:lazy_authorization) { lazy }

          context "when authorization is denied with its spans disabled" do
            let(:authorization_result) { false }
            let(:trace_options) { {trace_authorized: false} }

            it "still denies access to the object" do
              expect(result.to_h["data"]).to be_nil
              expect(span_name_resource_pairs("graphql.authorized", "graphql.authorized_lazy")).to be_empty
            end
          end

          [true, false].each do |enabled|
            context "with trace_authorized: #{enabled}" do
              let(:trace_options) { {trace_authorized: enabled} }

              it "#{enabled ? "creates" : "skips"} authorization spans" do
                expect(result.to_h).to eq("data" => {"item" => {"value" => resolved_value}})

                expected_spans = if !enabled
                  []
                elsif lazy
                  [
                    ["graphql.authorized", "SpanSelectionQuery.authorized"],
                    ["graphql.authorized", "SpanSelectionItem.authorized"],
                    ["graphql.authorized_lazy", "SpanSelectionItem.authorized"],
                  ]
                else
                  [
                    ["graphql.authorized", "SpanSelectionQuery.authorized"],
                    ["graphql.authorized", "SpanSelectionItem.authorized"],
                  ]
                end

                expect(span_name_resource_pairs("graphql.authorized", "graphql.authorized_lazy")).to match_array(expected_spans)
              end
            end
          end
        end
      end
    end

    describe "type resolution spans" do
      let(:query) { "{ item { ... on SpanSelectionItem { value } } }" }
      let(:item_return_type) do
        type = item_type
        stub_const("SpanSelectionUnion", Class.new(::GraphQL::Schema::Union) do
          possible_types type
        end)
      end

      before do
        type = item_type
        lazy = lazy_type_resolution
        schema.define_singleton_method(:resolve_type) do |_abstract_type, _object, _context|
          lazy ? ::GraphQL::Execution::Lazy.new { type } : type
        end
      end

      [false, true].each do |lazy|
        context "with #{lazy ? "lazy" : "synchronous"} type resolution" do
          let(:lazy_type_resolution) { lazy }

          [true, false].each do |enabled|
            context "with trace_resolve_type: #{enabled}" do
              let(:trace_options) { {trace_resolve_type: enabled} }

              it "#{enabled ? "creates" : "skips"} type resolution spans" do
                expect(result.to_h).to eq("data" => {"item" => {"value" => resolved_value}})

                expected_spans = if !enabled
                  []
                elsif lazy
                  [
                    ["graphql.resolve_type", "SpanSelectionUnion.resolve_type"],
                    ["graphql.resolve_type_lazy", "SpanSelectionUnion.resolve_type"],
                  ]
                else
                  [["graphql.resolve_type", "SpanSelectionUnion.resolve_type"]]
                end

                expect(span_name_resource_pairs("graphql.resolve_type", "graphql.resolve_type_lazy")).to match_array(expected_spans)
              end
            end
          end
        end
      end
    end
  end

  describe ".serialize_error_locations" do
    subject(:result) { described_class.serialize_error_locations(locations) }

    context "when locations is nil" do
      let(:locations) { nil }

      it "returns an empty array" do
        expect(result).to eq([])
      end
    end

    context "when locations is an array" do
      let(:locations) do
        [
          {"line" => 3, "column" => 10},
          {"line" => 7, "column" => 8},
        ]
      end

      it "maps locations to formatted strings" do
        expect(result).to eq(["3:10", "7:8"])
      end
    end

    context "when locations is an empty array" do
      let(:locations) { [] }

      it "returns an empty array" do
        expect(result).to eq([])
      end
    end
  end
end
