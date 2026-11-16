# frozen_string_literal: true

require "json"
require "socket"

require "spec/support/thread_helpers"

# Temporary reproducer for the flaky elasticsearch patcher spec
# (Net::ReadTimeout on master commit
# https://github.com/DataDog/dd-trace-rb/commit/160fdb6513ad5ce21f54da106f1658d1e0e37875).
#
# Serves the HTTP endpoints the spec exercises and delays the indexing
# request by DELAY_SECONDS, recreating the CI failure condition: the
# server accepts the request but responds slower than the client read
# timeout.
module ElasticsearchStallReproducer
  DELAY_SECONDS = 6

  # The elasticsearch gem rejects responses without the product header.
  RESPONSE_HEADERS = "Content-Type: application/json\r\n" \
                    "X-elastic-product: Elasticsearch\r\n" \
                    "Connection: close\r\n"

  # Boots the stub server and points the suite at it through the
  # TEST_ELASTICSEARCH_* environment variables.
  def self.start!
    server = TCPServer.new("127.0.0.1", 0)
    # The named thread group marks the server threads as intentional to the
    # suite's thread leak detector.
    ThreadHelpers.with_leaky_thread_creation("Elasticsearch stall reproducer") do
      Thread.new { accept_loop(server) }
    end
    ENV["TEST_ELASTICSEARCH_HOST"] = "127.0.0.1"
    ENV["TEST_ELASTICSEARCH_PORT"] = server.addr[1].to_s
  end

  def self.accept_loop(server)
    loop do
      Thread.new(server.accept) do |client|
        handle(client)
      ensure
        client.close
      end
    end
  end

  def self.handle(client)
    request_line = read_request(client)
    return unless request_line

    method, path = request_line.split(" ")
    path = path.to_s.sub(%r{\?.*$}, "")
    sleep(DELAY_SECONDS) if method == "PUT" && path == "/some_index/_doc/1"
    status, body = response(method, path)
    client.write(
      "HTTP/1.1 #{status}\r\n" \
      "#{RESPONSE_HEADERS}" \
      "Content-Length: #{body.bytesize}\r\n" \
      "\r\n" \
      "#{body}"
    )
  end

  def self.read_request(client)
    headers = +""
    while (line = client.gets)
      headers << line
      break if line == "\r\n"
    end
    content_length = headers[/Content-Length: (\d+)/i, 1].to_i
    client.read(content_length) if content_length.positive?
    headers.split("\r\n").first
  end

  def self.response(method, path)
    if method == "GET" && path == "/"
      [200, JSON.generate({"version" => {"number" => "9.5.0"}})]
    elsif method == "GET" && path == "/_cluster/health"
      [200, JSON.generate({"status" => "yellow"})]
    elsif method == "GET" && path == "/some_index/_doc/999"
      [404, JSON.generate({"found" => false})]
    elsif method == "PUT" && path == "/some_index/_doc/1"
      [201, JSON.generate({"result" => "created"})]
    else
      [404, JSON.generate({"error" => "unexpected #{method} #{path}"})]
    end
  end
end
