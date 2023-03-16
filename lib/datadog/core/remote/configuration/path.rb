# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      class Configuration
        # Path stores path information
        class Path
          class ParseError < StandardError; end

          class << self
            RE = %r{
              ^
              (?<source>
                datadog/(?<org_id>\d+)
                |
                employee
              )
              /
              (?<product>[^/]+)
              /
              (?<config_id>[^/]+)
              /
              (?<name>config)
              $
            }mx.freeze

            def parse(path)
              m = RE.match(path)

              raise ParseError, "could not parse: #{path.inspect}" if m.nil?

              # @type var org_id: ::Integer?
              org_id = _ = m['org_id'] ? m['org_id'].to_i : nil
              # @type var source: ::String
              source = _ = m['source']

              source = _ = source.delete("/#{org_id}") if org_id

              # @type var product: ::String
              product = _ = m['product']
              # @type var config_id: ::String
              config_id = _ = m['config_id']
              # @type var name: ::String
              name = _ = m['name']

              new(source: source, org_id: org_id, product: product, config_id: config_id, name: name)
            end
          end

          attr_reader :source, :org_id, :product, :config_id, :name

          def initialize(source:, product:, config_id:, name:, org_id: nil)
            @source = source
            @org_id = org_id
            @product = product
            @config_id = config_id
            @name = name
          end

          private_class_method :new

          def to_s
            if org_id
              "#{source}/#{org_id}/#{product}/#{config_id}/#{name}"
            else
              "#{source}/#{product}/#{config_id}/#{name}"
            end
          end

          def ==(other)
            return false unless other.is_a?(Path)

            to_s == other.to_s
          end

          def hash
            to_s.hash
          end

          def eql?(other)
            hash == other.hash
          end
        end
      end
    end
  end
end
