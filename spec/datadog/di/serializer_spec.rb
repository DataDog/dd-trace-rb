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

class DISerializerStackOverflowTestClass; end

class DISerializerOutOfMemoryTestClass; end

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
    with_di_registry_change

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

    context 'when condition raises an exception' do
      let(:telemetry) { double('telemetry') }
      let(:serializer) do
        described_class.new(settings, redactor, telemetry: telemetry)
      end

      it 'skips the custom serializer and uses default serialization' do
        # Register a custom serializer with a condition that raises an exception
        # This simulates a regex match against invalid UTF-8 strings
        described_class.register(condition: lambda { |value| value =~ /test/ }) do |serializer, value, name:, depth:|
          serializer.serialize_value('should not be called')
        end

        # Invalid UTF-8 string that will cause regex match to raise
        invalid_utf8 = "\x80\xFF".force_encoding(Encoding::UTF_8)
        expect(invalid_utf8.valid_encoding?).to be false

        # Expect logging and telemetry
        expect(Datadog.logger).to receive(:warn).with(/Custom serializer condition failed: ArgumentError/)
        expect(telemetry).to receive(:report).with(
          an_instance_of(ArgumentError),
          description: "Custom serializer condition failed"
        )

        serialized = serializer.serialize_value(invalid_utf8)

        # Should fall back to default serialization (binary escaping)
        expect(serialized[:type]).to eq('String')
        expect(serialized[:value]).to eq("b'\\x80\\xff'")
      end

      it 'continues checking other custom serializers after exception' do
        # Register a custom serializer with a condition that raises an exception
        described_class.register(condition: lambda { |value| value =~ /first/ }) do |serializer, value, name:, depth:|
          serializer.serialize_value('first serializer')
        end

        # Register another custom serializer that should work
        described_class.register(condition: lambda { |value| String === value && value.encoding == Encoding::UTF_8 && !value.valid_encoding? }) do |serializer, value, name:, depth:|
          {type: 'String', value: 'second serializer'}
        end

        invalid_utf8 = "\x80\xFF".force_encoding(Encoding::UTF_8)

        # Expect logging and telemetry for the first (failing) serializer
        expect(Datadog.logger).to receive(:warn).with(/Custom serializer condition failed: ArgumentError/)
        expect(telemetry).to receive(:report).with(
          an_instance_of(ArgumentError),
          description: "Custom serializer condition failed"
        )

        serialized = serializer.serialize_value(invalid_utf8)

        # Should skip the first (failing) serializer and use the second one
        expect(serialized[:type]).to eq('String')
        expect(serialized[:value]).to eq('second serializer')
      end
    end
  end

  context 'when serialization raises an exception' do
    with_di_registry_change

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

  describe 'binary data serialization' do
    context 'with high bytes' do
      # Create a shorter string with high bytes to avoid truncation
      let(:binary_string) do
        "\x80\x90\xa0\xb0\xc0\xd0\xe0\xf0\xff".b
      end

      it 'escapes binary data to JSON-safe format' do
        # Serialize the binary string
        serialized = serializer.serialize_value(binary_string)

        # The serializer produces an escaped string in b'...' format
        expect(serialized[:type]).to eq('String')
        expect(serialized[:value]).to eq("b'\\x80\\x90\\xa0\\xb0\\xc0\\xd0\\xe0\\xf0\\xff'")
        expect(serialized[:value].encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'in nested structures' do
      let(:binary_string) { "\x80\x81\x82\xFF\xFE".b }

      it 'escapes binary strings in vars' do
        # Simulate a more realistic snapshot with binary data in locals
        vars = {binary_data: binary_string, normal_string: "hello"}
        serialized = serializer.serialize_vars(vars)

        # Binary data is escaped
        expect(serialized[:binary_data][:type]).to eq('String')
        expect(serialized[:binary_data][:value]).to eq("b'\\x80\\x81\\x82\\xff\\xfe'")
        expect(serialized[:binary_data][:value].encoding).to eq(Encoding::UTF_8)

        # Normal string is unchanged
        expect(serialized[:normal_string][:type]).to eq('String')
        expect(serialized[:normal_string][:value]).to eq('hello')
        expect(serialized[:normal_string][:value].encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'in method arguments' do
      let(:binary_string) { "\x00\x01\x02\xFF".b }

      it 'escapes binary strings in args' do
        # Simulate method arguments containing binary data
        args = [binary_string, "normal arg"]
        kwargs = {data: binary_string}
        target_self = Object.new

        serialized = serializer.serialize_args(args, kwargs, target_self)

        # Binary data is escaped
        expect(serialized[:arg1][:type]).to eq('String')
        expect(serialized[:arg1][:value]).to eq("b'\\x00\\x01\\x02\\xff'")
        expect(serialized[:arg1][:value].encoding).to eq(Encoding::UTF_8)

        # Normal arg is unchanged
        expect(serialized[:arg2][:type]).to eq('String')
        expect(serialized[:arg2][:value]).to eq('normal arg')
        expect(serialized[:arg2][:value].encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'with mixed printable and binary data' do
      let(:binary_string) { "Hello\x00World\xFF".b }

      it 'escapes non-printable bytes while preserving printable ASCII' do
        serialized = serializer.serialize_value(binary_string)

        expect(serialized[:value]).to eq("b'Hello\\x00World\\xff'")
        expect(serialized[:value].encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'with special escape sequences' do
      let(:binary_string) { "Line1\nLine2\tTab\rReturn".b }

      it 'uses standard escape sequences' do
        serialized = serializer.serialize_value(binary_string)

        expect(serialized[:value]).to eq("b'Line1\\nLine2\\tTab\\rReturn'")
        expect(serialized[:value].encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'with quotes and backslashes' do
      let(:binary_string) { "It's a\\test".b }

      it 'escapes quotes and backslashes' do
        serialized = serializer.serialize_value(binary_string)

        expect(serialized[:value]).to eq("b'It\\'s a\\\\test'")
        expect(serialized[:value].encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'truncation behavior' do
      # Truncation is applied to the ORIGINAL binary data (in bytes) before escaping.
      # This is efficient - we only escape what we need rather than escaping a large
      # binary string and then throwing away most of the work.
      #
      # The size field reports the original binary data length in bytes.

      context 'when binary data is under the limit' do
        let(:binary_string) { "\xFF".b * 5 }

        before do
          allow(di_settings).to receive(:max_capture_string_length).and_return(10)
        end

        it 'does not truncate and escapes all bytes' do
          serialized = serializer.serialize_value(binary_string)

          # 5 bytes < 10 limit, no truncation
          # Escaped: b'\xff\xff\xff\xff\xff' = 2 + 5*4 + 1 = 23 chars
          expect(serialized[:value]).to eq("b'\\xff\\xff\\xff\\xff\\xff'")
          expect(serialized[:truncated]).to be_falsey
          expect(serialized[:size]).to be_nil
        end
      end

      context 'when binary data is at the exact limit' do
        let(:binary_string) { "\x00".b * 10 }

        before do
          allow(di_settings).to receive(:max_capture_string_length).and_return(10)
        end

        it 'does not truncate and escapes all bytes' do
          serialized = serializer.serialize_value(binary_string)

          # 10 bytes == 10 limit, no truncation
          # Escaped: b'\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' = 2 + 10*4 + 1 = 43 chars
          expect(serialized[:value]).to eq("b'\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00'")
          expect(serialized[:truncated]).to be_falsey
          expect(serialized[:size]).to be_nil
        end
      end

      context 'when binary data exceeds the limit' do
        let(:binary_string) { "\xFF".b * 20 }

        before do
          allow(di_settings).to receive(:max_capture_string_length).and_return(10)
        end

        it 'truncates original binary to limit then escapes' do
          serialized = serializer.serialize_value(binary_string)

          # 20 bytes > 10 limit, truncate to first 10 bytes
          # Escaped: b'\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff' = 2 + 10*4 + 1 = 43 chars
          expect(serialized[:value]).to eq("b'\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff'")
          expect(serialized[:truncated]).to be true
          expect(serialized[:size]).to eq(20) # Original size, not escaped size
        end
      end

      context 'with very large binary data' do
        let(:binary_string) { "\x80".b * 1000 }

        before do
          allow(di_settings).to receive(:max_capture_string_length).and_return(10)
        end

        it 'efficiently truncates before escaping' do
          serialized = serializer.serialize_value(binary_string)

          # 1000 bytes > 10 limit, truncate to first 10 bytes then escape
          # This is efficient: we escape 10 bytes, not 1000 bytes
          expect(serialized[:value]).to eq("b'\\x80\\x80\\x80\\x80\\x80\\x80\\x80\\x80\\x80\\x80'")
          expect(serialized[:truncated]).to be true
          expect(serialized[:size]).to eq(1000)
        end
      end

      context 'with mixed printable and non-printable bytes' do
        let(:binary_string) { "Hello\x00\x01\x02World\xFF".b }

        before do
          # 14 bytes total: Hello(5) + \x00\x01\x02(3) + World(5) + \xFF(1)
          allow(di_settings).to receive(:max_capture_string_length).and_return(8)
        end

        it 'truncates to byte limit before escaping' do
          serialized = serializer.serialize_value(binary_string)

          # 14 bytes > 8 limit, truncate to first 8 bytes: "Hello\x00\x01\x02"
          # Escaped: b'Hello\x00\x01\x02' = 2 + 5 + 4 + 4 + 4 + 1 = 20 chars
          expect(serialized[:value]).to eq("b'Hello\\x00\\x01\\x02'")
          expect(serialized[:truncated]).to be true
          expect(serialized[:size]).to eq(14)
        end
      end

      context 'size field reporting' do
        it 'reports original binary byte count, not escaped string length' do
          binary_string = "\xFF".b * 50
          allow(di_settings).to receive(:max_capture_string_length).and_return(10)

          serialized = serializer.serialize_value(binary_string)

          # Original: 50 bytes
          # Truncated to: 10 bytes
          # Escaped result would be 43 characters, but size reports original bytes
          expect(serialized[:size]).to eq(50) # Not 43
          expect(serialized[:truncated]).to be true
        end
      end
    end

    context 'with printable ASCII in binary string' do
      # Printable ASCII in binary strings is preserved during escaping
      let(:binary_string) { "Hello World! This is a test.".b }

      before do
        # 28 bytes total, limit to 20 bytes
        allow(di_settings).to receive(:max_capture_string_length).and_return(20)
      end

      it 'truncates to byte limit before escaping' do
        serialized = serializer.serialize_value(binary_string)

        # Original: 28 bytes
        # Truncate to first 20 bytes: "Hello World! This is"
        # Escape: b'Hello World! This is' = 23 chars
        expect(serialized[:value]).to eq("b'Hello World! This is'")
        expect(serialized[:truncated]).to be true
        expect(serialized[:size]).to eq(28) # Original byte count
      end
    end

    context 'regular UTF-8 string truncation' do
      # Verify that regular (non-binary) strings use character-based truncation
      it 'truncates based on character count for UTF-8 strings' do
        # 15 character string (no escaping needed)
        utf8_string = "Hello, World!!!"
        allow(di_settings).to receive(:max_capture_string_length).and_return(10)

        serialized = serializer.serialize_value(utf8_string)

        # Should truncate at 10 characters (not bytes)
        expect(serialized[:value]).to eq("Hello, Wor")
        expect(serialized[:truncated]).to be true
        expect(serialized[:size]).to eq(15)
      end

      it 'handles multi-byte UTF-8 characters correctly' do
        # String with emoji: "Hello 👋 World" = 13 characters (emoji is 1 char)
        utf8_string = "Hello 👋 World"
        allow(di_settings).to receive(:max_capture_string_length).and_return(8)

        serialized = serializer.serialize_value(utf8_string)

        # Should truncate at 8 characters: "Hello 👋 " (includes the space)
        expect(serialized[:value]).to eq("Hello 👋 ")
        expect(serialized[:truncated]).to be true
        expect(serialized[:size]).to eq(13)
      end

      it 'does not escape valid UTF-8 strings' do
        utf8_string = "Hello"
        allow(di_settings).to receive(:max_capture_string_length).and_return(100)

        serialized = serializer.serialize_value(utf8_string)

        # Should not have b'...' wrapping
        expect(serialized[:value]).to eq("Hello")
        expect(serialized[:truncated]).to be_falsey
      end
    end

    context 'with invalid UTF-8 strings' do
      it 'escapes strings marked as UTF-8 but with invalid byte sequences' do
        # String marked as UTF-8 but containing invalid bytes
        # This commonly happens when binary data is incorrectly tagged
        invalid_utf8 = "\x80\xFF".force_encoding(Encoding::UTF_8)
        expect(invalid_utf8.valid_encoding?).to be false

        result = serializer.serialize_value(invalid_utf8)

        # Should escape like binary data
        expect(result[:type]).to eq('String')
        expect(result[:value]).to eq("b'\\x80\\xff'")
        expect(result[:value].encoding).to eq(Encoding::UTF_8)

        # Should be JSON-serializable
        expect {
          JSON.dump(result)
        }.not_to raise_error
      end

      it 'escapes strings with mixed valid and invalid UTF-8 sequences' do
        # Valid UTF-8 text followed by invalid bytes
        invalid_utf8 = "Hello\x80World\xFF".force_encoding(Encoding::UTF_8)
        expect(invalid_utf8.valid_encoding?).to be false

        result = serializer.serialize_value(invalid_utf8)

        expect(result[:type]).to eq('String')
        expect(result[:value]).to eq("b'Hello\\x80World\\xff'")
        expect(result[:value].encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'with non-UTF8, non-Binary encodings' do
      it 'handles Latin1 (ISO-8859-1) strings with high-bit characters' do
        # Latin1 "é" (0xE9) - valid Latin1, not valid UTF-8 byte sequence
        latin1 = "\xE9".force_encoding(Encoding::ISO_8859_1)
        expect(latin1.encoding).to eq(Encoding::ISO_8859_1)
        expect(latin1.valid_encoding?).to be true # Valid Latin1

        result = serializer.serialize_value(latin1)

        # Should NOT escape (it's a valid encoding, not binary)
        # JSON.dump will transcode Latin1 to UTF-8 automatically
        expect(result[:type]).to eq('String')
        expect(result[:value]).not_to start_with("b'") # Not escaped
        expect(result[:value].encoding).to eq(Encoding::ISO_8859_1) # Preserved

        # Should be JSON-serializable (Ruby will transcode)
        expect {
          JSON.dump(result)
        }.not_to raise_error
      end

      it 'handles Latin1 strings with all high-bit bytes' do
        # All Latin1 high-bit characters (128-255)
        latin1 = (128..255).map { |i| i.chr(Encoding::ISO_8859_1) }.join
        expect(latin1.encoding).to eq(Encoding::ISO_8859_1)
        expect(latin1.valid_encoding?).to be true

        result = serializer.serialize_value(latin1)

        # Should NOT escape - it's a valid encoding
        expect(result[:type]).to eq('String')
        expect(result[:value]).not_to start_with("b'")
        expect(result[:value].encoding).to eq(Encoding::ISO_8859_1)

        # Should be JSON-serializable
        expect {
          json = JSON.dump(result)
          parsed = JSON.parse(json)
          # JSON transcodes to UTF-8
          expect(parsed['value'].encoding).to eq(Encoding::UTF_8)
        }.not_to raise_error
      end

      it 'handles Windows-1252 encoding' do
        # Windows-1252 specific character: € (0x80)
        windows1252 = "\x80".force_encoding(Encoding::Windows_1252)
        expect(windows1252.valid_encoding?).to be true

        result = serializer.serialize_value(windows1252)

        # Should NOT escape - it's a valid encoding
        expect(result[:type]).to eq('String')
        expect(result[:value]).not_to start_with("b'")
        expect(result[:value].encoding).to eq(Encoding::Windows_1252)

        # Should be JSON-serializable
        expect {
          JSON.dump(result)
        }.not_to raise_error
      end

      it 'truncates Latin1 strings based on character length' do
        # 20 character Latin1 string with high bits
        latin1 = "\xE9" * 20 # "é" repeated 20 times
        latin1 = latin1.force_encoding(Encoding::ISO_8859_1)
        allow(di_settings).to receive(:max_capture_string_length).and_return(10)

        result = serializer.serialize_value(latin1)

        # Should truncate at 10 characters (not bytes, not escape)
        expect(result[:value].length).to eq(10)
        expect(result[:value].encoding).to eq(Encoding::ISO_8859_1)
        expect(result[:truncated]).to be true
        expect(result[:size]).to eq(20)
      end
    end

    context 'with empty binary string' do
      let(:binary_string) { "".b }

      it 'produces empty escaped string' do
        serialized = serializer.serialize_value(binary_string)

        expect(serialized[:type]).to eq('String')
        expect(serialized[:value]).to eq("b''")
        expect(serialized[:value].encoding).to eq(Encoding::UTF_8)
        expect(serialized).not_to have_key(:truncated)
      end
    end

    context 'with very large binary string' do
      let(:binary_string) { ("\xFF" * 100_000).b }

      it 'truncates to max_capture_string_length' do
        # Default max is 100 in the test helper
        serialized = serializer.serialize_value(binary_string)

        # Truncate to first 100 bytes of binary, then escape
        # Escaped result: b' + 100*\xff + ' = 2 + 400 + 1 = 403 chars
        expect(serialized[:value].length).to eq(403)
        expect(serialized[:value]).to start_with("b'\\xff")
        expect(serialized[:value]).to end_with("'")
        expect(serialized[:truncated]).to be true

        # Size field reports original binary byte count
        expect(serialized[:size]).to eq(100_000)
      end

      it 'is JSON-serializable despite large size' do
        serialized = serializer.serialize_value(binary_string)

        expect {
          JSON.dump(serialized)
        }.not_to raise_error
      end
    end
  end

  context 'when custom serializer raises SystemStackError' do
    # SystemStackError typically occurs due to infinite recursion.
    # This test emulates a custom serializer that creates deeply nested structures
    # or has circular references, causing stack overflow during serialization.
    #
    # SystemStackError inherits from Exception, NOT StandardError.
    # The serializer's rescue clause at line 316 now catches Exception to handle
    # these cases gracefully by returning a structure with notSerializedReason.
    #
    # This prevents the exception from propagating to the transport layer and
    # ensures the rest of the snapshot can still be serialized and sent.

    with_di_registry_change

    before do
      # Register a custom serializer that raises SystemStackError
      # This simulates what happens when a serializer creates infinite recursion
      Datadog::DI::Serializer.register(
        condition: lambda { |value| DISerializerStackOverflowTestClass === value }
      ) do |*args|
        raise SystemStackError, "stack level too deep (emulated infinite recursion)"
      end
    end

    let(:telemetry) { double('telemetry') }
    let(:serializer) do
      described_class.new(settings, redactor, telemetry: telemetry)
    end

    describe "#serialize_value" do
      let(:value) { DISerializerStackOverflowTestClass.new }

      it 'returns safe structure with notSerializedReason when SystemStackError is raised' do
        allow(telemetry).to receive(:report)

        serialized = serializer.serialize_value(value)

        expect(serialized[:type]).to eq('DISerializerStackOverflowTestClass')
        expect(serialized[:notSerializedReason]).to match(/stack level too deep/)
        expect(serialized).not_to have_key(:value)
        expect(serialized).not_to have_key(:fields)
      end

      it 'returns JSON-serializable output despite SystemStackError' do
        allow(telemetry).to receive(:report)

        serialized = serializer.serialize_value(value)

        # The key test: can we JSON encode the result?
        # This should NOT raise because the serializer converts the error to a safe structure
        expect {
          json = JSON.dump(serialized)
          expect(json).to be_a(String)
          expect(json).to include('notSerializedReason')
          expect(json).to include('stack level too deep')
        }.not_to raise_error
      end

      it 'reports SystemStackError to telemetry' do
        expect(telemetry).to receive(:report).with(
          an_instance_of(SystemStackError),
          description: "Error serializing",
        )

        serializer.serialize_value(value)
      end
    end

    context 'in a snapshot with multiple values' do
      it 'isolates SystemStackError to one variable while successfully serializing others' do
        # A snapshot might contain multiple captured variables, some of which
        # serialize successfully and one that raises SystemStackError.
        # The exception is caught per-variable, so other values still serialize.
        vars = {
          normal_value: "hello",
          problematic_value: DISerializerStackOverflowTestClass.new,
          another_value: 42,
        }

        expect(telemetry).to receive(:report).with(
          an_instance_of(SystemStackError),
          description: "Error serializing",
        )

        serialized = serializer.serialize_vars(vars)

        expect(serialized[:normal_value][:type]).to eq('String')
        expect(serialized[:normal_value][:value]).to eq('hello')

        expect(serialized[:problematic_value][:type]).to eq('DISerializerStackOverflowTestClass')
        expect(serialized[:problematic_value][:notSerializedReason]).to match(/stack level too deep/)

        expect(serialized[:another_value][:type]).to eq('Integer')
        expect(serialized[:another_value][:value]).to eq('42')

        expect {
          JSON.dump(serialized)
        }.not_to raise_error
      end
    end
  end

  context 'when custom serializer raises NoMemoryError' do
    # NoMemoryError occurs when Ruby cannot allocate more memory.
    # This test emulates a custom serializer that attempts to create very large
    # structures (e.g., huge strings or arrays) that exceed available memory.
    #
    # NoMemoryError inherits from Exception, NOT StandardError.
    # The serializer's rescue clause at line 316 now catches Exception to handle
    # these cases gracefully by returning a structure with notSerializedReason.
    #
    # This prevents the exception from propagating to the transport layer and
    # ensures the rest of the snapshot can still be serialized and sent.
    #
    # In reality, NoMemoryError could occur when:
    # - A captured variable is extremely large (e.g., multi-GB string or array)
    # - The serializer attempts to duplicate or expand large objects
    # - String escaping operations on huge binary blobs exhaust memory

    with_di_registry_change

    before do
      # Register a custom serializer that raises NoMemoryError
      # This simulates what happens when trying to serialize extremely large objects
      Datadog::DI::Serializer.register(
        condition: lambda { |value| DISerializerOutOfMemoryTestClass === value }
      ) do |*args|
        raise NoMemoryError, "failed to allocate memory (emulated out of memory condition)"
      end
    end

    let(:telemetry) { double('telemetry') }
    let(:serializer) do
      described_class.new(settings, redactor, telemetry: telemetry)
    end

    describe "#serialize_value" do
      let(:value) { DISerializerOutOfMemoryTestClass.new }

      it 'returns safe structure with notSerializedReason when NoMemoryError is raised' do
        allow(telemetry).to receive(:report)

        serialized = serializer.serialize_value(value)

        expect(serialized[:type]).to eq('DISerializerOutOfMemoryTestClass')
        expect(serialized[:notSerializedReason]).to match(/failed to allocate memory/)
        expect(serialized).not_to have_key(:value)
        expect(serialized).not_to have_key(:fields)
      end

      it 'returns JSON-serializable output despite NoMemoryError' do
        allow(telemetry).to receive(:report)

        serialized = serializer.serialize_value(value)

        # The key test: can we JSON encode the result?
        # This should NOT raise because the serializer converts the error to a safe structure
        expect {
          json = JSON.dump(serialized)
          expect(json).to be_a(String)
          expect(json).to include('notSerializedReason')
          expect(json).to include('failed to allocate memory')
        }.not_to raise_error
      end

      it 'reports NoMemoryError to telemetry' do
        expect(telemetry).to receive(:report).with(
          an_instance_of(NoMemoryError),
          description: "Error serializing",
        )

        serializer.serialize_value(value)
      end
    end

    context 'in a snapshot with multiple values' do
      it 'isolates NoMemoryError to one variable while successfully serializing others' do
        # Even if one value causes NoMemoryError, others should still serialize.
        # The exception is caught per-variable, so other values still serialize.
        vars = {
          small_value: "tiny",
          huge_value: DISerializerOutOfMemoryTestClass.new,
          number: 123,
        }

        expect(telemetry).to receive(:report).with(
          an_instance_of(NoMemoryError),
          description: "Error serializing",
        )

        serialized = serializer.serialize_vars(vars)

        expect(serialized[:small_value][:type]).to eq('String')
        expect(serialized[:small_value][:value]).to eq('tiny')

        expect(serialized[:huge_value][:type]).to eq('DISerializerOutOfMemoryTestClass')
        expect(serialized[:huge_value][:notSerializedReason]).to match(/failed to allocate memory/)

        expect(serialized[:number][:type]).to eq('Integer')
        expect(serialized[:number][:value]).to eq('123')

        expect {
          JSON.dump(serialized)
        }.not_to raise_error
      end
    end
  end
end
