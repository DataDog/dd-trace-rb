# Please move everything to the right files
module Datadog
  module Core
    module Telemetry
      class Client
        def initialize(enabled: true, sequence: Datadog::Core::Utils::Sequence.new)
          @enabled = enabled
          @emitter = Emitter.new(sequence: sequence)

          @worker = Worker.new do
            heartbeat!
          end
        end

        def disable!
          @enabled = false
          @worker.disable!
        end

        def started!
          return unless @enable
          @emitter.request(request_type: 'app-started')
        end

        class Worker
          def initialize(sequence:, enabled: true, &block)
            @enabled = enabled
            @thread = Thread.new do
              loop do
                break if @enabled

                sleep(60)

                yield
              end
            end
          end

          def disable!
            @enabled = false
          end
        end

        def stop!
          return if @stopped
          worker.stop

          @stopped = true

          return unless @enable
          @emitter.request(request_type: 'app-closing')
        end

        private

        def heartbeat!
          @emitter.request(request_type: 'app-heartbeat')
        end
      end
    end
  end
end

# Module that emits telemetry events
class Emitter
  def initializer(sequence: Datadog::Core::Utils::Sequence.new, http_transport: Datadog::Core::Telemetry::Http::Transport.new)
    @sequence = sequence
    @http_transport = http_transport
  end

  def request(request_type)
    begin
      request = Datadog::Core::Telemetry::Event.new.telemetry_request(request_type: request_type, seq_id: sequence.next).to_h
      res = @http_transport.request(request_type: request_type, payload: request.to_json)
      # increment_seq_id if res.ok?
      res
    rescue StandardError => e
      Datadog.logger.info("Unable to send telemetry request for #{request_type}: #{e}")
    end
  end
end
