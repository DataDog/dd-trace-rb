# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      class Configuration
        class Content
          attr_reader :path, :data

          def initialize(path:, data:)
            @path = path
            @data = data
          end

          class << self
            def parse(hash)
              path = Path.parse(hash[:path])
              data = hash[:content]

              new(path: path, data: data)
            end
          end
        end

        class ContentList < Array
          def find(path, target)
            select { |c| c.path.eql?(path) && target.check(c) }.first
          end

          def [](path)
            select { |c| c.path.eql?(path) }.first
          end

          def paths
            map(&:path).uniq
          end

          class << self
            def parse(array)
              new.concat(array.map { |c| Content.parse(c) })
            end
          end
        end
      end
    end
  end
end
