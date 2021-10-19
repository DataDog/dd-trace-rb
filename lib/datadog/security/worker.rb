module Datadog
  module Security
    class Worker
      def initialize(options = {})
        transport_options = {}

        @transport = options.fetch(:transport) do
          Transport::HTTP.default(**transport_options)
        end
        @adapter = @transport.apis["v0.4"].adapter

        @mutex = Mutex.new
        @worker = nil
        @run = false
        @queue = Queue.new
      end

      def start
        @mutex.synchronize do
          return if @run

          @run = true
          Datadog.logger.debug { "Starting thread for: #{self}" }
          @worker = Thread.new { perform }
          @worker.name = self.class.name unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3')

          nil
        end
      end

      def stop
        @mutex.synchronize do
          return unless @run

          @queue.close
          @run = false
        end

        join
        true
      end

      def enqueue(events)
        @queue.push(events)
      end

      def perform
        loop do
          events = @queue.pop
          send_events(events)
          Datadog.logger.debug { "processed events: #{events.inspect}" }
        end
      end

      def send_events(events)
        path = '/appsec/proxy/api/v2/appsecevts'
        uri = URI("#{@adapter.ssl ? 'https' : 'http'}://#{@adapter.hostname}:#{@adapter.port}#{path}")
        Datadog.logger.debug { uri.to_s }

        begin
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            req = Net::HTTP::Post.new(uri.path)
            req['X-Api-Version'] = 'v0.1.0'
            req['Content-Type'] = 'application/json'
            req.body = JSON.dump({
              protocol_version: 1,
              idempotency_key: SecureRandom.uuid,
              events: events,
            })

            res = http.request(req)

            case res
            when Net::HTTPSuccess
              Datadog.logger.debug { "success" }
            else
              Datadog.logger.debug { "failed: #{res.inspect}" }
            end
          end
        rescue StandardError => e
          Datadog.logger.error { "Internal error during HTTP transport request. Cause: #{e.message}" }
        end
      end
    end
  end
end

