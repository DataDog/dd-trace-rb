require 'time'
require 'net/http'
require 'spec/support/synchronization_helpers'

module HttpHelpers
  def wait_http_server(server, delay)
    SynchronizationHelpers.try_wait_until(attempts: delay, backoff: 1) do |attempts_left|
      uri = URI("#{server}/")
      begin
        res = Net::HTTP.get_response(uri)
        return true if res.code == '200'
      rescue StandardError => e
        Datadog.logger.error("Failed waiting for http server #{e.message}") if attempts_left < 5
      end
    end
  end
end
