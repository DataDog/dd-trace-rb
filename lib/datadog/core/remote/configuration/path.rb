# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      class Configuration
        class Path
          attr_reader :source, :org_id, :product, :config_id, :name

          def initialize(source:, product:, config_id:, name:, org_id: nil)
            @source = source
            @org_id = org_id
            @product = product
            @config_id = config_id
            @name = name
          end

          def to_s
            "#{source}/#{product}/#{config_id}/#{name}"
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

              source = m['source']
              org_id = Integer(m['org_id']) unless m['org_id'].nil?
              product = m['product']
              config_id = m['config_id']
              name = m['name']

              new(source: source, org_id: org_id, product: product, config_id: config_id, name: name)
            end
          end

          class ParseError < StandardError; end
        end
      end
    end
  end
end
