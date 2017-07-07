require 'time'
require 'net/http'
require 'ddtrace'

Datadog::Monkey.patch_module(:http)

def wait_http_server(server, delay)
  delay.times do |i|
    uri = URI(server + '/')
    begin
      res = Net::HTTP.get_response(uri)
      return true if res.code == '200'
    rescue StandardError => e
      puts e if i >= 3 # display errors only when failing repeatedly
    end
    sleep 1
  end
  false
end
