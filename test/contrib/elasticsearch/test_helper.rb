require 'time'
require 'net/http'
require 'elasticsearch/transport'
require 'ddtrace/monkey'

Datadog::Monkey.patch_all

def wait_http_server(server, delay)
  delay.times do
    uri = URI(server + '/')
    begin
      res = Net::HTTP.get_response(uri)
      return true if res.code == '200'
    rescue StandardError => e
      puts e
    end
    sleep 1
  end
  false
end
