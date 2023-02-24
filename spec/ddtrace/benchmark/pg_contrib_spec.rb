require 'spec_helper'

require 'benchmark'
require 'ddtrace'
require 'pg'

RSpec.describe 'Pg Tracing Integration', :order => :defined do
  iterations = 1000

  let(:conn) do
    PG::Connection.new(
      host: host,
      port: port,
      dbname: dbname,
      user: user,
      password: password
    )
  end

  let(:host) { ENV.fetch('TEST_POSTGRES_HOST') { '127.0.0.1' } }
  let(:port) { ENV.fetch('TEST_POSTGRES_PORT') { '5432' } }
  let(:dbname) { ENV.fetch('TEST_POSTGRES_DB') { 'postgres' } }
  let(:user) { ENV.fetch('TEST_POSTGRES_USER') { 'postgres' } }
  let(:password) { ENV.fetch('TEST_POSTGRES_PASSWORD') { 'postgres' } }

  after do
    conn.close
  end

  context 'timing' do
    before { skip('Benchmark results not currently captured in CI') if ENV.key?('CI') }

    include Benchmark

    context 'no tracing enabled' do
      context 'SELECT 1' do
        before { conn.prepare('SELECT 1', 'SELECT $1::int') }
        it {
          Benchmark.benchmark(Benchmark::CAPTION, 30, Benchmark::FORMAT) do |x|
            x.report('#exec') { iterations.times { conn.exec('SELECT 1;') } }
            x.report('#exec_params') { iterations.times { conn.exec_params('SELECT $1::int;', [1]) } }
            x.report('#exec_prepared') { iterations.times { conn.exec_prepared('SELECT 1', [1]) } }
            x.report('#async_exec') { iterations.times { conn.async_exec('SELECT 1;') } }
            x.report('#async_exec_params') { iterations.times { conn.async_exec_params('SELECT $1::int;', [1]) } }
            x.report('#async_exec_prepared') { iterations.times { conn.async_exec_prepared('SELECT 1', [1]) } }
            x.report('#sync_exec') { iterations.times { conn.sync_exec('SELECT 1;') } }
            x.report('#sync_exec_params') { iterations.times { conn.sync_exec_params('SELECT $1::int;', [1]) } }
            x.report('#sync_exec_prepared') { iterations.times { conn.sync_exec_prepared('SELECT 1', [1]) } }
          end
        }
      end

      context 'SELECT * FROM 100 rows' do
        before do
          conn.exec('CREATE TABLE test_table (col1 text, col2 text, col3 text);')
          100.times { conn.exec("INSERT INTO test_table (col1,col2,col3) VALUES ('foo','bar','baz');") }
          conn.prepare('SELECT test_table', 'SELECT $1::text, $2::text, $3::text FROM test_table')
        end
        after { conn.exec('DROP TABLE test_table;') }
        it {
          Benchmark.benchmark(Benchmark::CAPTION, 30, Benchmark::FORMAT) do |x|
            x.report('#exec') { iterations.times { conn.exec('SELECT * FROM test_table;') } }
            x.report('#exec_params') do
              iterations.times do
                conn.exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#exec_prepared') do
              iterations.times do
                conn.exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
            x.report('#async_exec') { iterations.times { conn.async_exec('SELECT * FROM test_table;') } }
            x.report('#async_exec_params') do
              iterations.times do
                conn.async_exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#async_exec_prepared') do
              iterations.times do
                conn.async_exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
            x.report('#sync_exec') { iterations.times { conn.sync_exec('SELECT * FROM test_table;') } }
            x.report('#sync_exec_params') do
              iterations.times do
                conn.sync_exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#sync_exec_prepared') do
              iterations.times do
                conn.sync_exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
          end
        }
      end

      context 'SELECT * FROM 1000 rows' do
        before do
          conn.exec('CREATE TABLE test_table (col1 text, col2 text, col3 text);')
          1000.times { conn.exec("INSERT INTO test_table (col1,col2,col3) VALUES ('foo','bar','baz');") }
          conn.prepare('SELECT test_table', 'SELECT $1::text, $2::text, $3::text FROM test_table')
        end
        after { conn.exec('DROP TABLE test_table;') }
        it {
          Benchmark.benchmark(Benchmark::CAPTION, 30, Benchmark::FORMAT) do |x|
            x.report('#exec') { iterations.times { conn.exec('SELECT * FROM test_table;') } }
            x.report('#exec_params') do
              iterations.times do
                conn.exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#exec_prepared') do
              iterations.times do
                conn.exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
            x.report('#async_exec') { iterations.times { conn.async_exec('SELECT * FROM test_table;') } }
            x.report('#async_exec_params') do
              iterations.times do
                conn.async_exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#async_exec_prepared') do
              iterations.times do
                conn.async_exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
            x.report('#sync_exec') { iterations.times { conn.sync_exec('SELECT * FROM test_table;') } }
            x.report('#sync_exec_params') do
              iterations.times do
                conn.sync_exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#sync_exec_prepared') do
              iterations.times do
                conn.sync_exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
          end
        }
      end
    end

    context 'tracing enabled' do
      before do
        Datadog.configure do |c|
          c.tracing.instrument :pg
        end
        conn.exec('SELECT 1;') # to warm up the library
      end
      context 'SELECT 1' do
        before { conn.prepare('SELECT 1', 'SELECT $1::int') }
        it {
          Benchmark.benchmark(Benchmark::CAPTION, 30, Benchmark::FORMAT) do |x|
            x.report('#exec') { iterations.times { conn.exec('SELECT 1;') } }
            x.report('#exec_params') { iterations.times { conn.exec_params('SELECT $1::int;', [1]) } }
            x.report('#exec_prepared') { iterations.times { conn.exec_prepared('SELECT 1', [1]) } }
            x.report('#async_exec') { iterations.times { conn.async_exec('SELECT 1;') } }
            x.report('#async_exec_params') { iterations.times { conn.async_exec_params('SELECT $1::int;', [1]) } }
            x.report('#async_exec_prepared') { iterations.times { conn.async_exec_prepared('SELECT 1', [1]) } }
            x.report('#sync_exec') { iterations.times { conn.sync_exec('SELECT 1;') } }
            x.report('#sync_exec_params') { iterations.times { conn.sync_exec_params('SELECT $1::int;', [1]) } }
            x.report('#sync_exec_prepared') { iterations.times { conn.sync_exec_prepared('SELECT 1', [1]) } }
          end
        }
      end

      context 'SELECT * FROM 100 rows' do
        before do
          conn.exec('CREATE TABLE test_table (col1 text, col2 text, col3 text);')
          100.times { conn.exec("INSERT INTO test_table (col1,col2,col3) VALUES ('foo','bar','baz');") }
          conn.prepare('SELECT test_table', 'SELECT $1::text, $2::text, $3::text FROM test_table')
        end
        after { conn.exec('DROP TABLE test_table;') }
        it {
          Benchmark.benchmark(Benchmark::CAPTION, 30, Benchmark::FORMAT) do |x|
            x.report('#exec') { iterations.times { conn.exec('SELECT * FROM test_table;') } }
            x.report('#exec_params') do
              iterations.times do
                conn.exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#exec_prepared') do
              iterations.times do
                conn.exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
            x.report('#async_exec') { iterations.times { conn.async_exec('SELECT * FROM test_table;') } }
            x.report('#async_exec_params') do
              iterations.times do
                conn.async_exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#async_exec_prepared') do
              iterations.times do
                conn.async_exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
            x.report('#sync_exec') { iterations.times { conn.sync_exec('SELECT * FROM test_table;') } }
            x.report('#sync_exec_params') do
              iterations.times do
                conn.sync_exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#sync_exec_prepared') do
              iterations.times do
                conn.sync_exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
          end
        }
      end

      context 'SELECT * FROM 1000 rows' do
        before do
          conn.exec('CREATE TABLE test_table (col1 text, col2 text, col3 text);')
          1000.times { conn.exec("INSERT INTO test_table (col1,col2,col3) VALUES ('foo','bar','baz');") }
          conn.prepare('SELECT test_table', 'SELECT $1::text, $2::text, $3::text FROM test_table')
        end
        after { conn.exec('DROP TABLE test_table;') }
        it {
          Benchmark.benchmark(Benchmark::CAPTION, 30, Benchmark::FORMAT) do |x|
            x.report('#exec') { iterations.times { conn.exec('SELECT * FROM test_table;') } }
            x.report('#exec_params') do
              iterations.times do
                conn.exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#exec_prepared') do
              iterations.times do
                conn.exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
            x.report('#async_exec') { iterations.times { conn.async_exec('SELECT * FROM test_table;') } }
            x.report('#async_exec_params') do
              iterations.times do
                conn.async_exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#async_exec_prepared') do
              iterations.times do
                conn.async_exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
            x.report('#sync_exec') { iterations.times { conn.sync_exec('SELECT * FROM test_table;') } }
            x.report('#sync_exec_params') do
              iterations.times do
                conn.sync_exec_params('SELECT $1::text, $2::text, $3::text FROM test_table;', %w[col1 col2 col3])
              end
            end
            x.report('#sync_exec_prepared') do
              iterations.times do
                conn.sync_exec_prepared('SELECT test_table', %w[col1 col2 col3])
              end
            end
          end
        }
      end
    end
  end
end
