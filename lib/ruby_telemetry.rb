# frozen_string_literal: true

require 'active_support/notifications'

raise unless RubyVM::YJIT.enabled?

# High performance event emitter
module RubyTelemetry
  class Channel
    def initialize
      @subscribers = []
    end

    def publish(message=nil, &block)
      @subscribers.each do |s|
        s.call(message)
      end
    end

    def safe_publishing(message=nil, &block)
      @subscribers.each do |s|
        s.call(message)
      rescue => e
        exceptions ||= []
        exceptions << e
      end
    end

    def subscribe(&block)
      @subscribers << block
      return block
    end

    def subscribed?
      @subscribers.empty?
    end

    def unsubscribe(subscription)
      @subscribers.delete(subscription)
    end
  end

  class EmtpyChannel < Channel
    def publish(message=nil, &block)
    end

    def subscribed?
      false
    end
  end

  class OneChannel < Channel
    def publish(message=nil, &block)
      @subscriber.call
    end

    def subscribe(&block)
      @subscriber = block
      return block
    end

    def subscribed?
      true
    end
  end
end

require 'benchmark/ips'
require 'benchmark-memory'

empty_channel = RubyTelemetry::EmtpyChannel.new

ActiveSupport::Notifications.subscribe('one') {}
one_channel = RubyTelemetry::Channel.new
one_channel.subscribe{}

one_channel_opt = RubyTelemetry::OneChannel.new
one_channel_opt.subscribe{}

ten_channel = RubyTelemetry::Channel.new
10.times do
  ActiveSupport::Notifications.subscribe('ten') {}
  ten_channel.subscribe{}
end

Benchmark.ips do |x|
  x.time = 5
  x.warmup = 1

  x.report('empty  as') { ActiveSupport::Notifications.publish('name', 'event') }
  x.report('empty new') { empty_channel.publish('event') }

  x.report('one  as') { ActiveSupport::Notifications.publish('one', 'event') }
  x.report('one new') { one_channel.publish('one') }
  x.report('one new safe') { one_channel.safe_publishing('one') }
  x.report('one new opt') { one_channel_opt.publish('one') }

  x.report('ten  as') { ActiveSupport::Notifications.publish('ten', 'event') }
  x.report('ten new') { ten_channel.publish('ten') }

  x.compare!
end


# require 'benchmark/ips'
# require 'benchmark-memory'
#
# def empty_method
# end
#
# Benchmark.ips do |x|
#   x.time = 5
#   x.warmup = 1
#
#   x.report('empty_method') { empty_method }
#   x.report('nothing') { }
#
#   x.compare!
# end

# 3.2
#              nothing: 29670439.9 i/s
#         empty_method: 26897040.1 i/s - 1.10x  slower

# 3.3-preview3
#         empty_method: 27276632.0 i/s
#              nothing: 26884731.5 i/s - same-ish: difference falls within error

# require 'benchmark/ips'
# require 'benchmark-memory'
#
# def publish_m(message)
# end
#
# def publish_m_b(message=nil, &block)
# end
#
# def publish_b(&block)
# end
#
# def publish_n()
# end
#
# Benchmark.ips do |x|
#   x.time = 5
#   x.warmup = 1
#
#   x.report('publish_m') { publish_m(1) }
#   x.report('publish_m_b_m') { publish_m_b(1) }
#   x.report('publish_m_b_b') { publish_m_b { 1 } }
#   x.report('publish_b') { publish_b { 1 } }
#   x.report('publish_n') { publish_n }
#
#
#   x.compare!
# end


#            empty new: 15975168.9 i/s
#          one new opt:  6825501.4 i/s - 2.34x  slower
