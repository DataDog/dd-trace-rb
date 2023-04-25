# frozen_string_literal: true

require_relative 'path'
require_relative 'digest'

module Datadog
  module Core
    module Remote
      class Configuration
        # Content stores the information associated with a specific Configuration::Path
        class Content
          class << self
            def parse(hash)
              path = Path.parse(hash[:path])
              data = hash[:content]

              new(path: path, data: data)
            end
          end

          attr_reader :path, :data, :hashes
          attr_accessor :version

          def initialize(path:, data:)
            @path = path
            @data = data
            @hashes = {}
            @version = 0
          end

          def hexdigest(type)
            @hashes[type] || compute_and_store_hash(type)
          end

          def length
            @length ||= @data.size
          end

          private

          def compute_and_store_hash(type)
            @hashes[type] = Digest.hexdigest(type, @data)
          end

          private_class_method :new
        end

        # ContentList stores a list of Conetnt instances
        # It provides convinient methods for finding content base on Configuration::Path and Configuration::Target
        class ContentList < Array
          class << self
            def parse(array)
              new.concat(array.map { |c| Content.parse(c) })
            end
          end

          def find_content(path, target)
            find { |c| c.path.eql?(path) && target.check(c) }
          end

          def [](path)
            find { |c| c.path.eql?(path) }
          end

          def []=(path, content)
            map! { |c| c.path.eql?(path) ? content : c }
          end

          def delete(path)
            idx = index { |e| e.path.eql?(path) }

            return if idx.nil?

            delete_at(idx)
          end

          def paths
            map(&:path).uniq
          end
        end
      end
    end
  end
end
