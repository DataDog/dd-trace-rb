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

class DISerializerCustomExceptionTestClass < StandardError; end

class DISerializerExceptionWithFieldsTestClass < StandardError
  def initialize(message)
    super
    @test_field = 'bar'
  end
end

class DISerializerExceptionWithMessageFieldTestClass < StandardError
  def initialize(message)
    super
    @message = 'bar'
  end
end

class DISerializerExceptionWithMessageRaiseTestClass < StandardError
  def initialize(message)
    super
    @message = 'bar'
  end

  def message
    raise 'uh oh'
  end
end

class DISerializerSpecBrokenHash < Hash
  def keys
    raise "Arrgh!"
  end
end

class DISerializerSpecFields
  def initialize(**fields)
    fields.each do |k, v|
      instance_variable_set("@#{k}", v)
    end
  end
end

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
       expected_matches: {type: 'Time', value: %r{\A2020-01-02T03:04:05[-+]\d\d:\d\d\z}}},
      {name: 'Date value', input: Date.new(2020, 1, 2),
       expected: {type: 'Date', value: '2020-01-02'}},
      {name: 'DateTime value', input: DateTime.new(2020, 1, 2, 3, 4, 5),
       expected: {type: 'DateTime', value: '2020-01-02T03:04:05+00:00'}},

      # Exception classes do not have a dedicated serializer, but document
      # the lack of serialization of their messages (because we cannot do
      # so safely - guaranteeing not to invoke customer code).
      {name: 'Exception instance', input: IOError.new('test error'),
       expected: {type: 'IOError', fields: {}}},
      {name: 'Exception instance with a field', input: DISerializerExceptionWithFieldsTestClass.new('test error'),
       expected: {type: 'DISerializerExceptionWithFieldsTestClass', fields: {
         "@test_field": {
           value: 'bar', type: 'String'
         }
       }}},
      {name: 'Exception instance with @message field', input: DISerializerExceptionWithMessageFieldTestClass.new('test error'),
       expected: {type: 'DISerializerExceptionWithMessageFieldTestClass', fields: {
         "@message": {
           value: 'bar', type: 'String'
         }
       }}},
      {name: 'Custom exception instance which raises in #message', input: DISerializerExceptionWithMessageRaiseTestClass.new('test error'),
       expected: {type: 'DISerializerExceptionWithMessageRaiseTestClass', fields: {
         # Fields are still serialized.
         "@message": {
           value: 'bar', type: 'String'
         }
       }}},
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
      serializer.serialize_args(args, kwargs, target_self)
    end

    cases = [
      {name: "both args and kwargs",
       args: [1, "x"],
       kwargs: {a: 42},
       target_self: Object.new,
       expected: {arg1: {type: "Integer", value: "1"},
                  arg2: {type: "String", value: "x"},
                  a: {type: "Integer", value: "42"},
                  self: {type: 'Object', fields: {}},}},
      {name: "args, kwargs and instance vars",
       args: [1, "x"],
       kwargs: {a: 42},
       target_self: DISerializerSpecInstanceVariable.new('quux'),
       expected: {arg1: {type: "Integer", value: "1"},
                  arg2: {type: "String", value: "x"},
                  a: {type: "Integer", value: "42"},
                  self: {
                    type: 'DISerializerSpecInstanceVariable',
                    fields: {
                      "@ivar": {type: 'String', value: 'quux'},
                    },
                  },},},
      {name: "kwargs contains redacted identifier",
       args: [1, "x"],
       kwargs: {password: 42},
       target_self: Object.new,
       expected: {arg1: {type: "Integer", value: "1"},
                  arg2: {type: "String", value: "x"},
                  password: {type: "Integer", notCapturedReason: "redactedIdent"},
                  self: {type: 'Object', fields: {}},}},
    ]

    cases.each do |c|
      args = c.fetch(:args)
      kwargs = c.fetch(:kwargs)
      target_self = c.fetch(:target_self)
      expected = c.fetch(:expected)

      context c.fetch(:name) do
        let(:args) { args }
        let(:kwargs) { kwargs }
        let(:target_self) { target_self }

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
      let(:target_self) { Object.new }

      it 'preserves original value' do
        serialized

        args.first.gsub!('hello', 'bye')

        expect(serialized).to eq(
          arg1: {type: 'String', value: 'hello'},
          arg2: {type: 'String', value: 'world'},
          self: {type: 'Object', fields: {}},
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

      let(:target_self) { Object.new }

      it 'preserves original value' do
        serialized

        kwargs[:foo].gsub!('bar', 'bye')

        expect(serialized).to eq(
          foo: {type: 'String', value: 'bar'},
          self: {type: 'Object', fields: {}},
        )
      end
    end

    context 'when positional arg is frozen' do
      let(:frozen_string) { 'hello'.freeze }

      let(:args) do
        [frozen_string, 'world']
      end

      let(:kwargs) { {} }
      let(:target_self) { Object.new }

      it 'serializes without duplication' do
        expect(serialized).to eq(
          arg1: {type: 'String', value: 'hello'},
          arg2: {type: 'String', value: 'world'},
          self: {type: 'Object', fields: {}},
        )

        expect(serialized[:arg1][:value]).to be frozen_string
      end
    end

    context 'when keyword arg is frozen' do
      let(:frozen_string) { 'hello'.freeze }

      let(:args) { [] }

      let(:kwargs) { {foo: frozen_string} }
      let(:target_self) { Object.new }

      it 'serializes without duplication' do
        expect(serialized).to eq(
          foo: {type: 'String', value: 'hello'},
          self: {type: 'Object', fields: {}},
        )

        expect(serialized[:foo][:value]).to be frozen_string
      end
    end
  end

  describe '#serialize_string_or_symbol_for_message' do
    [
      [100, 'short', 'short'],
      [100, 'short1234', 'short1234'],
      # Truncation where the max length is too short for the ellipsis
      [4, 'short', 'shor'],
      # Minimum space for ellipsis but there is no need to truncate
      [5, 'short', 'short'],
      # Minimum space for ellipsis and truncation is happening
      [5, 'short1', 's...1'],
      [5, :short1, 's...1'],
      # Limited to 100
      [1000, 'long42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42long', 'long42longlong42longlong42longlong42longlong42lon...ng42longlong42longlong42longlong42longlong42long'],
      [1000, 'long42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42long1', 'long42longlong42longlong42longlong42longlong42lon...g42longlong42longlong42longlong42longlong42long1'],
      [99, 'long42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42long', 'long42longlong42longlong42longlong42longlong42lo...ng42longlong42longlong42longlong42longlong42long'],
      [99, 'long42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42longlong42long1', 'long42longlong42longlong42longlong42longlong42lo...g42longlong42longlong42longlong42longlong42long1'],
    ].each do |max_length, input, expected_output|
      context "max length: #{max_length}, input: #{input}" do
        # Verify our expected output is not longer than the max length
        it 'output not exceed max length' do
          expect(expected_output.length).to be <= max_length
        end

        context 'serialize' do
          before do
            expect(di_settings).to receive(:max_capture_string_length).and_return(max_length)
          end

          it 'produces expected output' do
            expect(serializer.send(:serialize_string_or_symbol_for_message, input)).to eq(expected_output)
          end
        end
      end
    end
  end

  describe '#serialize_value_for_message' do
    [
      ['nil', nil, 'nil'],
      ['integer', 42, '42'],
      ['float', 42.1, '42.1'],
      ['true', true, 'true'],
      ['false', false, 'false'],
      ['time', Time.utc(2020, 1, 2, 3, 4, 5), '2020-01-02 03:04:05 UTC'],
      ['date', Date.new(2020, 1, 2), '2020-01-02'],
      ['string', 'hello world', 'hello world'],
      ['long string', 'loooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooong string', 'loooooooooooooooooooooooooooooooooooooooooooooooo...ooooooooooooooooooooooooooooooooooooooong string'],
      ['symbol', :"hello world", ':hello world'],
      ['empty array', [], '[]'],
      ['small array', [1, '2'], '[1, 2]'],
      ['large array', [1, '2', 3.3, 'hello'], '[1, 2, ..., hello]'],
      ['empty hash', {}, '{}'],
      ['small hash', {a: 1, b: 2}, '{:a => 1, :b => 2}'],
      ['large hash', {:a => 1, :b => 2, 'c' => 3, 'd' => 4}, '{:a => 1, :b => 2, ..., d => 4}'],
      ['array with hash element', [{a: 1}, 2], '[..., 2]'],
      ['array with object element', [Object.new, 2], '[..., 2]'],
      ['hash with array value', {a: [1, 2], b: 3}, '{:a => ..., :b => 3}'],
      ['hash with object value', {a: Object.new, b: 3}, '{:a => ..., :b => 3}'],
      ['object without fields', Object.new, '#<Object>'],
      ['object with few fields', DISerializerSpecFields.new(a: 1, b: 2), '#<DISerializerSpecFields @a=1 @b=2>'],
      ['object with many fields', DISerializerSpecFields.new(a: 1, b: 2, c: 'x', d: 4, e: 4, f: 5), '#<DISerializerSpecFields @a=1 @b=2 @c=x @d=4 ... @f=5>'],
      ['object with array field', DISerializerSpecFields.new(a: 1, b: [2]), '#<DISerializerSpecFields @a=1 @b=...>'],
      ['object with hash field', DISerializerSpecFields.new(a: 1, b: {x: 2}), '#<DISerializerSpecFields @a=1 @b=...>'],
      ['when serialization fails', DISerializerSpecBrokenHash.new, '#<DISerializerSpecBrokenHash: serialization error>'],
    ].each do |desc, input, expected_output|
      context desc do
        let(:actual) do
          serializer.serialize_value_for_message(input)
        end

        it 'produces expected output' do
          expect(actual).to eq(expected_output)
        end
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
