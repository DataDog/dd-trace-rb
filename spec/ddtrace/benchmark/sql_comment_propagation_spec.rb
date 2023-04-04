require 'spec_helper'

require 'benchmark/ips'
require 'ddtrace'
require 'mysql2'

RSpec.describe 'SQL comment propagation', :order => :defined do
  before { skip('Benchmark results not currently captured in CI') if ENV.key?('CI') }

  describe 'with `mysql2' do
    let(:host) { ENV.fetch('TEST_MYSQL_HOST') { '127.0.0.1' } }
    let(:port) { ENV.fetch('TEST_MYSQL_PORT') { '3306' } }
    let(:database) { ENV.fetch('TEST_MYSQL_DB') { 'mysql' } }
    let(:username) { ENV.fetch('TEST_MYSQL_USER') { 'root' } }
    let(:password) { ENV.fetch('TEST_MYSQL_PASSWORD') { 'root' } }

    context 'benchmark' do
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

      context 'without db connection' do
        context 'SELECT 1' do
          it do
            mock_client = Class.new do
              include Datadog::Tracing::Contrib::Mysql2::Instrumentation

              attr_reader :query_options

              def initialize(query_options)
                @query_options = query_options
              end

              def query(sql, options = {})
                nil
              end
            end

            mock_disabled_client = Class.new(mock_client) do
              def comment_propagation
                'disabled'
              end
            end

            mock_service_client = Class.new(mock_client) do
              def comment_propagation
                'service'
              end
            end

            mock_full_client = Class.new(mock_client) do
              def comment_propagation
                'full'
              end
            end

            client_1 = mock_disabled_client.new(hash)
            client_2 = mock_service_client.new(hash)
            client_3 = mock_full_client.new(hash)

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

      context 'with db connection' do
        context 'SELECT 1' do
          it do
            test_client = Class.new(Mysql2::Client) do
              def query(sql, options = {})
                super(sql, options)
              end
            end

            test_disabled_client = Class.new(test_client) do
              def comment_propagation
                'disabled'
              end
            end

            test_service_client = Class.new(test_client) do
              def comment_propagation
                'service'
              end
            end

            test_full_client = Class.new(test_client) do
              def comment_propagation
                'full'
              end
            end

            client_1 = test_disabled_client.new(hash)
            client_2 = test_service_client.new(hash)
            client_3 = test_full_client.new(hash)

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
end
