module Datadog
  module Security
    # Instrumentation for Security
    module Instrumentation
      # Instrumentation gateway implementation
      # TODO: this is going away soon
      class Gateway
        def initialize
          @listeners = {}
        end

        def push(event_name, data)
          event_callbacks = @listeners[event_name]

          if event_callbacks
            r = nil
            event_callbacks.each { |e| break if (r = e.call(data)) }
            r
          end
        end

        def watch(event_name, &block)
          (@listeners[event_name] ||= []) << block
        end

        # def hook(method)
        #   gateway = self

        #   Graft::Hook[method] do
        #     before do |data|
        #       gateway.push(data)
        #     end
        #   end
        # end
      end

      # Graft::Hook['foo#bar'].add do
      #   Gateway.push('foo_bar_event', data)
      # end

      # Gateway.hook('foo#bar') do
      #   data # returned
      # end

      # Gateway.watch('foo_bar_event') do |data|
      # ...
      # end

      def self.gateway
        @gateway ||= Gateway.new
      end
    end
  end
end
