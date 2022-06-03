require_relative '../app/pg'
require 'pg'

RSpec.describe 'pg' do
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

  context '#create_table' do
    subject(:call_create_table) { create_table(conn) }
    let(:select_table) { conn.exec("SELECT * from pg_catalog.pg_tables WHERE tablename='test_table';") }
    after { conn.exec("DROP TABLE IF EXISTS test_table;") }
    it 'creates a test_table' do
      call_create_table
      expect(select_table).to have_attributes(:ntuples => 1)
    end
  end
end
