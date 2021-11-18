require 'datadog/security/reactive/address_hash'
require 'datadog/security/reactive/subscriber'

module Datadog
  module Security
    module Reactive
      # Reactive Engine
      class Engine
        def initialize
          @data = {}
          @subscribers = AddressHash.new { |h, k| h[k] = [] }
          @children = []
        end

        def subscribe(*addresses, &block)
          @subscribers[addresses.freeze] << Subscriber.new(&block).freeze
        end

        def publish(address, data)
          # check if someone has address subscribed
          if @subscribers.addresses.include?(address)

            # someone will be interested, set data
            @data[address] = data

            # find candidates i.e address groups that contain the just posted address
            @subscribers.with(address).each do |addresses|
              # find targets to the address group containing the posted address
              subscribers = @subscribers[addresses]

              # is all data for the targets available?
              if (addresses - @data.keys).empty?
                hash = addresses.each_with_object({}) { |a, h| h[a] = @data[a] }
                subscribers.each { |s| s.call(*hash.values) }
              end
            end
          end
        end
      end
    end
  end
end
