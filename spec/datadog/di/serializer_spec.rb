require "datadog/di/spec_helper"
require "datadog/di/serializer"
require_relative 'serializer_helper'

class DISerializerSpecSensitiveType
end

class DISerializerSpecWildCardClass; end

class DISerializerSpecInstanceVariable
  def initialize(value)
    @ivar = value
  end
end

class DISerializerSpecRedactedInstanceVariable
  def initialize(value)
    @session = value
  end
end

class DISerializerSpecManyInstanceVariables
  def initialize
    1.upto(100) do |i|
      instance_variable_set("@v#{i}", i)
    end
  end
end

# Should have no instance variables
class DISerializerSpecTestClass; end

class DISerializerCustomExceptionTestClass; end

RSpec.describe Datadog::DI::Serializer do
  di_test

  extend SerializerHelper

  default_settings

  let(:redactor) do
    Datadog::DI::Redactor.new(settings)
  end

  let(:serializer) do
    described_class.new(settings, redactor)
  end

  describe "#serialize_value" do
    let(:serialized) do
      serializer.serialize_value(value, **options)
    end

    cases = [
      {name: "nil value", input: nil, expected: {type: "NilClass", isNull: true}},
      {name: "true value", input: true, expected: {type: "TrueClass", value: "true"}},
      {name: "false value", input: false, expected: {type: "FalseClass", value: "false"}},
      {name: "int value", input: 42, expected: {type: "Integer", value: "42"}},
      {name: "bigint value", input: 420000000000000000000042, expected: {type: "Integer", value: "420000000000000000000042"}},
      {name: "float value", input: 42.02, expected: {type: "Float", value: "42.02"}},
      {name: "string value", input: "x", expected: {type: "String", value: "x"}},
      {name: "symbol value", input: :x, expected: {type: "Symbol", value: "x"}},
      {name: "redacted identifier in predefined list", input: "123", var_name: "password",
       expected: {type: "String", notCapturedReason: "redactedIdent"}},
      {name: "variable name given and is not a redacted identifier", input: "123", var_name: "normal",
       expected: {type: "String", value: "123"}},
      # We can assert exact value when the time zone is UTC,
      # since we don't know the local time zone ahead of time.
      {name: 'Time value in UTC', input: Time.utc(2020, 1, 2, 3, 4, 5),
        expected: {type: 'Time', value: '2020-01-02T03:04:05Z'}},
      {name: 'Time value in local time zone', input: Time.local(2020, 1, 2, 3, 4, 5),
        expected_matches: {type: 'Time', value: %r,\A2020-01-02T03:04:05[-+]\d\d:\d\d\z, }},
      {name: 'Date value', input: Date.new(2020, 1, 2),
        expected: {type: 'Date', value: '2020-01-02'}},
      {name: 'DateTime value', input: DateTime.new(2020, 1, 2, 3, 4, 5),
        expected: {type: 'DateTime', value: '2020-01-02T03:04:05+00:00'}},
    ]

    define_serialize_value_cases(cases)
  end

  describe "#serialize_vars" do
    let(:serialized) do
      serializer.serialize_vars(vars)
    end

    def self.define_cases(cases)
      cases.each do |c|
        value = c.fetch(:input)
        expected = c.fetch(:expected)

        context c.fetch(:name) do
          let(:vars) { value }

          it "serializes as expected" do
            expect(serialized).to eq(expected)
          end
        end
      end
    end

    cases = [
      {name: "redacted value in predefined list", input: {password: "123"},
       expected: {password: {type: "String", notCapturedReason: "redactedIdent"}}},
      {name: "redacted type", input: {value: DISerializerSpecSensitiveType.new},
       expected: {value: {type: "DISerializerSpecSensitiveType", notCapturedReason: "redactedType"}}},
      {name: "redacted wild card type", input: {value: DISerializerSpecWildCardClass.new},
       expected: {value: {type: "DISerializerSpecWildCardClass", notCapturedReason: "redactedType"}}},
      {name: "empty array", input: {arr: []},
       expected: {arr: {type: "Array", elements: []}}},
      {name: "array of primitives", input: {arr: [42, "hello", nil, true]},
       expected: {arr: {type: "Array", elements: [
         {type: "Integer", value: "42"},
         {type: "String", value: "hello"},
         {type: "NilClass", isNull: true},
         {type: "TrueClass", value: "true"},
       ]}}},
      {name: "array with value of redacted type", input: {arr: [1, DISerializerSpecSensitiveType.new]},
       expected: {arr: {type: "Array", elements: [
         {type: "Integer", value: "1"},
         {type: "DISerializerSpecSensitiveType", notCapturedReason: "redactedType"},
       ]}}},
      {name: "empty hash", input: {h: {}}, expected: {h: {type: "Hash", entries: []}}},
      {name: "hash with symbol key", input: {h: {hello: 42}}, expected: {h: {type: "Hash", entries: [
        [{type: "Symbol", value: "hello"}, {type: "Integer", value: "42"}],
      ]}}},
      {name: "hash with string key", input: {h: {"hello" => 42}}, expected: {h: {type: "Hash", entries: [
        [{type: "String", value: "hello"}, {type: "Integer", value: "42"}],
      ]}}},
      {name: "hash with redacted identifier", input: {h: {"session-key" => 42}}, expected: {h: {type: "Hash", entries: [
        [{type: "String", value: "session-key"}, {type: "Integer", notCapturedReason: "redactedIdent"}],
      ]}}},
      {name: "empty object", input: {x: Object.new}, expected: {x: {type: "Object", fields: {}}}},
      {name: "object with instance variable", input: {x: DISerializerSpecInstanceVariable.new(42)},
       expected: {x: {type: "DISerializerSpecInstanceVariable", fields: {
         "@ivar": {type: "Integer", value: "42"},
       }}}},
      {name: "object with redacted instance variable", input: {x: DISerializerSpecRedactedInstanceVariable.new(42)},
       expected: {x: {type: "DISerializerSpecRedactedInstanceVariable", fields: {
         "@session": {type: "Integer", notCapturedReason: "redactedIdent"},
       }}}},
      {name: "depth exceeded: array", input: {v: {a: {b: {c: []}}}},
       expected: {v: {type: "Hash", entries: [
         [{type: "Symbol", value: "a"}, {type: "Hash", entries: [
           [{type: "Symbol", value: "b"}, {type: "Hash", entries: [
             [{type: "Symbol", value: "c"}, {type: "Array", notCapturedReason: "depth"}],
           ]}],
         ]}],
       ]}}},
      {name: "depth exceeded: hash", input: {v: {a: {b: {c: {}}}}},
       expected: {v: {type: "Hash", entries: [
         [{type: "Symbol", value: "a"}, {type: "Hash", entries: [
           [{type: "Symbol", value: "b"}, {type: "Hash", entries: [
             [{type: "Symbol", value: "c"}, {type: "Hash", notCapturedReason: "depth"}],
           ]}],
         ]}],
       ]}}},
      {name: "depth exceeded: object", input: {v: {a: {b: {c: Object.new}}}},
       expected: {v: {type: "Hash", entries: [
         [{type: "Symbol", value: "a"}, {type: "Hash", entries: [
           [{type: "Symbol", value: "b"}, {type: "Hash", entries: [
             [{type: "Symbol", value: "c"}, {type: "Object", notCapturedReason: "depth"}],
           ]}],
         ]}],
       ]}}},
      {name: "object with no attributes", input: {v: DISerializerSpecTestClass.new},
       expected: {v: {type: "DISerializerSpecTestClass", fields: {}}},},
      {name: "object of anonymous class with no attributes", input: {v: Class.new.new},
       expected: {v: {type: "[Unnamed class]", fields: {}}},},
      # TODO hash with a complex object as key?
    ]

    define_cases(cases)

    context "when data exceeds collection limits" do
      before do
        allow(di_settings).to receive(:max_capture_collection_size).and_return(3)
      end

      cases = [
        {name: "array too long", input: {a: [10] * 1000},
         expected: {a: {type: "Array",
                        elements: [
                          {type: "Integer", value: "10"},
                          {type: "Integer", value: "10"},
                          {type: "Integer", value: "10"},
                        ], notCapturedReason: "collectionSize", size: 1000}}},
        {name: "hash too long", input: {v: {a: 1, b: 2, c: 3, d: 4, e: 5}},
         expected: {v: {type: "Hash",
                        entries: [
                          [{type: "Symbol", value: "a"}, {type: "Integer", value: "1"}],
                          [{type: "Symbol", value: "b"}, {type: "Integer", value: "2"}],
                          [{type: "Symbol", value: "c"}, {type: "Integer", value: "3"}],
                        ], notCapturedReason: "collectionSize", size: 5}}},
      ]

      define_cases(cases)
    end

    context "when data exceeds attribute limits" do
      before do
        allow(di_settings).to receive(:max_capture_attribute_count).and_return(3)
      end

      cases = [
        {name: "too many attributes", input: {a: DISerializerSpecManyInstanceVariables.new},
         expected: {a: {type: "DISerializerSpecManyInstanceVariables",
                        fields: {
                          "@v1": {type: "Integer", value: "1"},
                          "@v2": {type: "Integer", value: "2"},
                          "@v3": {type: "Integer", value: "3"},
                        }, notCapturedReason: "fieldCount"}}},
      ]

      define_cases(cases)
    end

    context "when strings exceed max length" do
      before do
        allow(di_settings).to receive(:max_capture_string_length).and_return(3)
      end

      cases = [
        {name: "string too long", input: {a: "abcde"},
         expected: {a: {type: "String", value: "abc", size: 5, truncated: true}}},
        {name: "symbol too long", input: {a: :abcde},
         expected: {a: {type: "Symbol", value: "abc", size: 5, truncated: true}}},
      ]

      define_cases(cases)
    end

    context "when limits are zero" do
      before do
        allow(di_settings).to receive(:max_capture_collection_size).and_return(0)
      end

      cases = [
        {name: "array", input: {a: [10] * 5},
         expected: {a: {type: "Array",
                        elements: [
                          {type: "Integer", value: "10"},
                          {type: "Integer", value: "10"},
                          {type: "Integer", value: "10"},
                          {type: "Integer", value: "10"},
                          {type: "Integer", value: "10"},
                        ]}}},
        {name: "hash", input: {v: {a: 1, b: 2, c: 3, d: 4, e: 5}},
         expected: {v: {type: "Hash",
                        entries: [
                          [{type: "Symbol", value: "a"}, {type: "Integer", value: "1"}],
                          [{type: "Symbol", value: "b"}, {type: "Integer", value: "2"}],
                          [{type: "Symbol", value: "c"}, {type: "Integer", value: "3"}],
                          [{type: "Symbol", value: "d"}, {type: "Integer", value: "4"}],
                          [{type: "Symbol", value: "e"}, {type: "Integer", value: "5"}],
                        ]}}},
      ]

      define_cases(cases)
    end
  end

  describe "#serialize_args" do
    let(:serialized) do
      serializer.serialize_args(args, kwargs)
    end

    cases = [
      {name: "both args and kwargs",
       args: [1, "x"],
       kwargs: {a: 42},
       expected: {arg1: {type: "Integer", value: "1"},
                  arg2: {type: "String", value: "x"},
                  a: {type: "Integer", value: "42"}},},
      {name: "kwargs contains redacted identifier",
       args: [1, "x"],
       kwargs: {password: 42},
       expected: {arg1: {type: "Integer", value: "1"},
                  arg2: {type: "String", value: "x"},
                  password: {type: "Integer", notCapturedReason: "redactedIdent"}},},
    ]

    cases.each do |c|
      args = c.fetch(:args)
      kwargs = c.fetch(:kwargs)
      expected = c.fetch(:expected)

      context c.fetch(:name) do
        let(:args) { args }
        let(:kwargs) { kwargs }

        it "serializes as expected" do
          expect(serialized).to eq(expected)
        end
      end
    end

    context 'when positional arg is mutated' do
      let(:args) do
        ['hello', 'world']
      end

      let(:kwargs) { {} }

      it 'preserves original value' do
        serialized

        args.first.gsub!('hello', 'bye')

        expect(serialized).to eq(
          arg1: {type: 'String', value: 'hello'},
          arg2: {type: 'String', value: 'world'},
        )
      end
    end

    context 'when keyword arg is mutated' do
      let(:args) do
        []
      end

      let(:kwargs) do
        {foo: 'bar'}
      end

      it 'preserves original value' do
        serialized

        kwargs[:foo].gsub!('bar', 'bye')

        expect(serialized).to eq(
          foo: {type: 'String', value: 'bar'},
        )
      end
    end

    context 'when positional arg is frozen' do
      let(:frozen_string) { 'hello'.freeze }

      let(:args) do
        [frozen_string, 'world']
      end

      let(:kwargs) { {} }

      it 'serializes without duplication' do
        expect(serialized).to eq(
          arg1: {type: 'String', value: 'hello'},
          arg2: {type: 'String', value: 'world'},
        )

        expect(serialized[:arg1][:value]).to be frozen_string
      end
    end

    context 'when keyword arg is frozen' do
      let(:frozen_string) { 'hello'.freeze }

      let(:args) { [] }

      let(:kwargs) { {foo: frozen_string} }

      it 'serializes without duplication' do
        expect(serialized).to eq(
          foo: {type: 'String', value: 'hello'},
        )

        expect(serialized[:foo][:value]).to be frozen_string
      end
    end
  end

  describe '.register' do
    context 'with condition' do
      before do
        described_class.register(condition: lambda { |value| String === value && value =~ /serializer spec hello/ }) do |serializer, value, name:, depth:|
          serializer.serialize_value('replacement value')
        end
      end

      let(:expected) do
        {type: 'String', value: 'replacement value'}
      end

      it 'invokes custom serializer' do
        serialized = serializer.serialize_value('serializer spec hello world')
        expect(serialized).to eq(expected)
      end
    end
  end

  context 'when serialization raises an exception' do
    before do
      # Register a custom serializer that will raise an exception
      Datadog::DI::Serializer.register(condition: lambda { |value| DISerializerCustomExceptionTestClass === value }) do |*args|
        raise "Test exception"
      end
    end

    describe "#serialize_value" do
      let(:serialized) do
        serializer.serialize_value(value, **options)
      end

      cases = [
        {name: "serializes other values", input: {a: DISerializerCustomExceptionTestClass.new, b: 1},
          expected: {type: "Hash", entries: [
            [{type: 'Symbol', value: 'a'}, {type: 'DISerializerCustomExceptionTestClass', notSerializedReason: 'Test exception'}],
            [{type: 'Symbol', value: 'b'}, {type: 'Integer', value: '1'}],
          ]}},
      ]

      define_serialize_value_cases(cases)
    end
  end
end
