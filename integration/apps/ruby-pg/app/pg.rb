require_relative 'datadog'

def create_table(conn)
  res = conn.exec("CREATE TABLE IF NOT EXISTS test_table (id int, name text);")
  res
end

def send_queries
  conn = PG.connect( dbname: ENV['POSTGRES_DB'], host: ENV['POSTGRES_HOST'], user: ENV['POSTGRES_USER'], password: ENV['POSTGRES_PASSWORD'] )
  create_table(conn)
  loop do
    conn.exec("SELECT * FROM test_table;")
    sleep(1)
  end
end

send_queries if __FILE__ == $PROGRAM_NAME
