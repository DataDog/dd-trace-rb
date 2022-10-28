# typed: ignore

require 'spec_helper'

require 'benchmark/ips'
require 'ddtrace'
require 'mysql2'

RSpec.describe '`mysql2` Tracing Integration', :order => :defined do

  let(:host) { ENV.fetch('TEST_MYSQL_HOST') { '127.0.0.1' } }
  let(:port) { ENV.fetch('TEST_MYSQL_PORT') { '3306' } }
  let(:database) { ENV.fetch('TEST_MYSQL_DB') { 'mysql' } }
  let(:username) { ENV.fetch('TEST_MYSQL_USER') { 'root' } }
  let(:password) { ENV.fetch('TEST_MYSQL_PASSWORD') { 'root' } }

  context 'timing' do
    before { skip('Benchmark results not currently captured in CI') if ENV.key?('CI') }

    before do
      Datadog.configure do |c|
        c.env = 'production'
        c.service = 'myservice'
        c.version = '1.0.0'
        c.tracing.instrument :mysql2
      end
    end

    let(:hash) do
      {
        host: host,
        port: port,
        database: database,
        username: username,
        password: password
      }
    end
    let(:sql_statement) { 'SELECT 1;' }

    context 'without db' do
      context 'SELECT 1' do
        it do
          class MockClient
            include Datadog::Tracing::Contrib::Mysql2::Instrumentation
            attr_reader :query_options
            def initialize(query_options)
              @query_options = query_options
            end

            def query(sql, options = {})
              nil
            end
          end

          class MockDisabledClient < MockClient
            def comment_propagation
              'disabled'
            end
          end

          class MockServiceClient < MockClient
            def comment_propagation
              'service'
            end
          end

          class MockFullClient < MockClient
            def comment_propagation
              'full'
            end
          end

          client_1 = MockDisabledClient.new(hash)
          client_2 = MockServiceClient.new(hash)
          client_3 = MockFullClient.new(hash)

          client_1.query(sql_statement)
          client_2.query(sql_statement)
          client_3.query(sql_statement)

          sleep 1

          Benchmark.ips do |x|
            x.report('disabled') { client_1.query(sql_statement) }
            x.report('service') { client_2.query(sql_statement) }
            x.report('full') { client_3.query(sql_statement) }

            x.compare!
          end
        end
      end
    end

    context 'with db' do
      context 'SELECT 1' do
        it do
          class TestClient < Mysql2::Client
            def query(sql, options = {})
              super(sql, options)
            end
          end

          class TestDisabledClient < TestClient
            def comment_propagation
              'disabled'
            end
          end

          class TestServiceClient < TestClient
            def comment_propagation
              'service'
            end
          end

          class TestFullClient < TestClient
            def comment_propagation
              'full'
            end
          end

          client_1 = TestDisabledClient.new(hash)
          client_2 = TestServiceClient.new(hash)
          client_3 = TestFullClient.new(hash)

          client_1.query(sql_statement)
          client_2.query(sql_statement)
          client_3.query(sql_statement)

          sleep 1

          Benchmark.ips do |x|
            x.report('disabled') { client_1.query(sql_statement) }
            x.report('service') { client_2.query(sql_statement) }
            x.report('full') { client_3.query(sql_statement) }

            x.compare!
          end
        end
      end
    end
  end
end
