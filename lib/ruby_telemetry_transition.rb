# frozen_string_literal: true

RubyVM::YJIT.enable
raise unless RubyVM::YJIT.enabled?

# High performance event emitter
module RubyTelemetry
  class ActiveChannel
    def initialize
      @subscribers = []
    end

    def publish(message=nil, &block)
      @subscribers.each do |s|
        s.call(message)
      end
    end

    def subscribe(&block)
      @subscribers << block
      block
    end

    def subscribed?
      @subscribers.empty?
    end

    def unsubscribe(subscription)
      @subscribers.delete(subscription)

      # make_inactive if @subscribers.empty?
    end
  end

  module EmptyChannel
    def publish(message=nil, &block)
    end

    def subscribe(&block)
      make_active
      subscribe(&block)
    end

    def subscribed?
      false
    end

    def unsubscribe(subscription)
    end

    private

    ACTIVE_METHOD_PUBLISH = ActiveChannel.instance_method(:publish)
    ACTIVE_METHOD_SUBSCRIBE = ActiveChannel.instance_method(:subscribe)
    ACTIVE_METHOD_SUBSCRIBED = ActiveChannel.instance_method(:subscribed?)
    ACTIVE_METHOD_UNSUBSCRIBE = ActiveChannel.instance_method(:unsubscribe)
    private_constant :ACTIVE_METHOD_PUBLISH, :ACTIVE_METHOD_SUBSCRIBE, :ACTIVE_METHOD_SUBSCRIBED, :ACTIVE_METHOD_UNSUBSCRIBE

    def make_active
      define_singleton_method(:publish, ACTIVE_METHOD_PUBLISH)
      define_singleton_method(:subscribe, ACTIVE_METHOD_SUBSCRIBE)
      define_singleton_method(:subscribed?, ACTIVE_METHOD_SUBSCRIBED)
      define_singleton_method(:unsubscribe, ACTIVE_METHOD_UNSUBSCRIBE)
    end

    INACTIVE_METHOD_PUBLISH = instance_method(:publish)
    INACTIVE_METHOD_SUBSCRIBE = instance_method(:subscribe)
    INACTIVE_METHOD_SUBSCRIBED = instance_method(:subscribed?)
    INACTIVE_METHOD_UNSUBSCRIBE = instance_method(:unsubscribe)
    private_constant :INACTIVE_METHOD_PUBLISH, :INACTIVE_METHOD_SUBSCRIBE, :INACTIVE_METHOD_SUBSCRIBED, :INACTIVE_METHOD_UNSUBSCRIBE

    def make_inactive
      define_singleton_method(:publish, INACTIVE_METHOD_PUBLISH)
      define_singleton_method(:subscribe, INACTIVE_METHOD_SUBSCRIBE)
      define_singleton_method(:subscribed?, INACTIVE_METHOD_SUBSCRIBED)
      define_singleton_method(:unsubscribe, INACTIVE_METHOD_UNSUBSCRIBE)
    end
  end
  
  class Channel < ActiveChannel
    prepend EmptyChannel
  end
end

require 'benchmark/ips'
require 'benchmark-memory'

empty_channel_opt = RubyTelemetry::Channel.new
empty_channel = RubyTelemetry::Channel.new
empty_channel.send(:make_active)

one_channel = RubyTelemetry::Channel.new
one_channel.subscribe{}

ten_channel = RubyTelemetry::Channel.new
10.times do
  ten_channel.subscribe{}
end

Benchmark.ips do |x|
  x.time = 5
  x.warmup = 1

  x.report('empty opt') { empty_channel_opt.publish('event') }
  x.report('empty') { empty_channel.publish('event') }
  x.report('one sub') { one_channel.publish('one') }
  x.report('ten sub') { ten_channel.publish('ten') }

  x.compare!
end

# With YJIT
# Comparison:
#            empty opt: 51260567.5 i/s
#                empty: 40032548.0 i/s - 1.28x  slower
#              one sub: 16210204.6 i/s - 3.16x  slower
#              ten sub:  2525557.2 i/s - 20.30x  slower

# No YJIT
# Comparison:
#            empty opt: 19495860.3 i/s
#                empty: 14954888.8 i/s - 1.30x  slower
#              one sub:  8630363.4 i/s - 2.26x  slower
#              ten sub:  2098185.6 i/s - 9.29x  slower
