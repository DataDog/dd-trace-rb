module Datadog
  module Contrib
    # Registry is a collection of integrations.
    class Registry
      include Enumerable

      Entry = Struct.new(:name, :klass, :auto_patch)

      def initialize
        @data = {}
        @mutex = Mutex.new
      end

      def add(name, klass, auto_patch = false)
        @mutex.synchronize do
          @data[name] = Entry.new(name, klass, auto_patch).freeze
        end
      end

      def each
        @mutex.synchronize do
          @data.each { |_, entry| yield(entry) }
        end
      end

      def [](name)
        @mutex.synchronize do
          entry = @data[name]
          entry.klass if entry
        end
      end

      def to_h
        @mutex.synchronize do
          @data.each_with_object({}) do |(_, entry), hash|
            hash[entry.name] = entry.auto_patch
          end
        end
      end
    end
  end
end
