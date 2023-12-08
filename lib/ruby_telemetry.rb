# frozen_string_literal: true

raise unless RubyVM::YJIT.enabled?

# High performance event emitter
module RubyTelemetry
  class Channel
    def publish(message, &block)
    end

    def publish(message, &block)
    end

    def subscribe(&block)
      return block
    end

    def subscribed?
    end

    def unsubscribe(subscription) end
  end
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