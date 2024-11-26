require 'datadog/tracing/contrib/rails/rails_helper'
require "datadog/di/spec_helper"
require "datadog/di/serializer"
require_relative '../../serializer_helper'
require 'active_record'
require "datadog/di/contrib/active_record"

class SerializerRailsSpecTestEmptyModel < ActiveRecord::Base
end

class SerializerRailsSpecTestBasicModel < ActiveRecord::Base
end

RSpec.describe Datadog::DI::Serializer do
  di_test

  extend SerializerHelper

  before(:all) do
    @original_config = begin
      if defined?(::ActiveRecord::Base.connection_db_config)
        ::ActiveRecord::Base.connection_db_config
      else
        ::ActiveRecord::Base.connection_config
      end
    rescue ActiveRecord::ConnectionNotEstablished
    end

    ActiveRecord::Base.establish_connection(mysql_connection_string)

    ActiveRecord::Schema.define(version: 20161003090450) do
      create_table 'serializer_rails_spec_test_empty_models', force: :cascade do |t|
      end

      create_table 'serializer_rails_spec_test_basic_models', force: :cascade do |t|
        t.string 'title'
        t.datetime 'created_at', null: false
        t.datetime 'updated_at', null: false
      end
    end
  end

  def mysql
    {
      database: ENV.fetch('TEST_MYSQL_DB', 'mysql'),
      host: ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'),
      password: ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root'),
      port: ENV.fetch('TEST_MYSQL_PORT', '3306')
    }
  end

  def mysql_connection_string
    "mysql2://root:#{mysql[:password]}@#{mysql[:host]}:#{mysql[:port]}/#{mysql[:database]}"
  end

  after(:all) do
    ::ActiveRecord::Base.establish_connection(@original_config) if @original_config
  end

  let(:redactor) do
    Datadog::DI::Redactor.new(settings)
  end

  default_settings

  let(:serializer) do
    described_class.new(settings, redactor)
  end

  describe "#serialize_value" do
    let(:serialized) do
      serializer.serialize_value(value, **options)
    end

    cases = [
      {name: "AR model with no attributes",
       input: -> { SerializerRailsSpecTestEmptyModel.new },
       expected: {type: "SerializerRailsSpecTestEmptyModel", entries: [[
         {type: 'Symbol', value: 'attributes'},
         {type: 'Hash', entries: [[{type: 'String', value: 'id'}, {type: 'NilClass', isNull: true}]]},
       ], [
         {type: 'Symbol', value: 'new_record'},
         {type: 'TrueClass', value: 'true'},
       ]]}},
      {name: "AR model with empty attributes",
       input: -> { SerializerRailsSpecTestBasicModel.new },
       expected: {type: "SerializerRailsSpecTestBasicModel", entries: [[
         {type: 'Symbol', value: 'attributes'},
         {type: 'Hash', entries: [
           [{type: 'String', value: 'id'}, {type: 'NilClass', isNull: true}],
           [{type: 'String', value: 'title'}, {type: 'NilClass', isNull: true}],
           [{type: 'String', value: 'created_at'}, {type: 'NilClass', isNull: true}],
           [{type: 'String', value: 'updated_at'}, {type: 'NilClass', isNull: true}],
         ]},
       ], [
         {type: 'Symbol', value: 'new_record'},
         {type: 'TrueClass', value: 'true'},
       ]]}},
      {name: "AR model with filled out attributes",
       input: -> {
                SerializerRailsSpecTestBasicModel.new(
                  title: 'Hello, world!', created_at: Time.utc(2020, 1, 2), updated_at: Time.utc(2020, 1, 3)
                )
              },
       expected: {type: "SerializerRailsSpecTestBasicModel", entries: [[
         {type: 'Symbol', value: 'attributes'},
         {type: 'Hash', entries: [
           [{type: 'String', value: 'id'}, {type: 'NilClass', isNull: true}],
           [{type: 'String', value: 'title'}, {type: 'String', value: 'Hello, world!'}],
           [{type: 'String', value: 'created_at'}, {type: 'Time', value: '2020-01-02T00:00:00Z'}],
           [{type: 'String', value: 'updated_at'}, {type: 'Time', value: '2020-01-03T00:00:00Z'}],
         ]},
       ], [
         {type: 'Symbol', value: 'new_record'},
         {type: 'TrueClass', value: 'true'},
       ]]}},
      {name: "AR model with filled out attributes and persisted",
       input: -> {
                SerializerRailsSpecTestBasicModel.create!(
                  title: 'Hello, world!', created_at: Time.utc(2020, 1, 2), updated_at: Time.utc(2020, 1, 3)
                )
              },
       expected: {type: "SerializerRailsSpecTestBasicModel", entries: [[
         {type: 'Symbol', value: 'attributes'},
         {type: 'Hash', entries: [
           [{type: 'String', value: 'id'}, {type: 'Integer', value: '1'}],
           [{type: 'String', value: 'title'}, {type: 'String', value: 'Hello, world!'}],
           [{type: 'String', value: 'created_at'}, {type: 'Time', value: '2020-01-02T00:00:00Z'}],
           [{type: 'String', value: 'updated_at'}, {type: 'Time', value: '2020-01-03T00:00:00Z'}],
         ]},
       ], [
         {type: 'Symbol', value: 'new_record'},
         {type: 'FalseClass', value: 'false'},
       ]]}},
    ]

    define_serialize_value_cases(cases)
  end
end
