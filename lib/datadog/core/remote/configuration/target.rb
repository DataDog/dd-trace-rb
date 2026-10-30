# frozen_string_literal: true

require_relative "path"
require_relative "digest"
require_relative "error"
require_relative "json_coercion"

module Datadog
  module Core
    module Remote
      class Configuration
        # TargetMap stores information regarding Configuration::Path and Configuration::Target
        class TargetMap < Hash
          class << self
            def parse(hash)
              signed = hash.fetch("signed")
              raise Configuration::Error.invalid_data_type(signed, field: "signed", expected_type: Hash) unless signed.is_a?(Hash)

              # The +custom+ subtree is optional: a missing or non-object
              # subtree yields no opaque backend state.
              custom = signed["custom"]
              opaque_backend_state = custom.is_a?(Hash) ? custom["opaque_backend_state"] : nil
              opaque_backend_state = opaque_backend_state.is_a?(String) ? opaque_backend_state : nil
              # The version appears to be optional to the rest of this class,
              # and we have tests that do not provide it.
              version = JSONCoercion.coerce_integer(signed["version"])

              map = new

              map.instance_eval do
                @opaque_backend_state = opaque_backend_state
                @version = version
              end

              targets = signed.fetch("targets")
              raise Configuration::Error.invalid_data_type(targets, field: "targets", expected_type: Hash) unless targets.is_a?(Hash)

              targets.each_with_object(map) do |(p, t), m|
                path = Configuration::Path.parse(p)
                raise Configuration::Error.invalid_data_type(t, field: "targets entry", expected_type: Hash) unless t.is_a?(Hash)
                target = Configuration::Target.parse(t)

                m[path] = target
              end
            end
          end

          attr_reader :opaque_backend_state, :version

          def initialize
            super

            @opaque_backend_state = nil
            @version = nil
          end

          private_class_method :new
        end

        # Target stores digest information
        class Target
          class << self
            def parse(hash)
              raw_length = hash.fetch("length")
              length = JSONCoercion.coerce_integer(raw_length)
              raise Configuration::Error.invalid_data_type(raw_length, field: "length", expected_type: Integer) if length.nil?

              hashes = hash.fetch("hashes")
              raise Configuration::Error.invalid_data_type(hashes, field: "hashes", expected_type: Hash) unless hashes.is_a?(Hash)
              digests = Configuration::DigestList.parse(hashes)

              custom = hash["custom"]
              raw_version = custom.is_a?(Hash) ? custom["v"] : nil
              version = JSONCoercion.coerce_integer(raw_version)
              raise Configuration::Error.invalid_data_type(raw_version, field: "custom.v", expected_type: Integer) if version.nil?

              new(digests: digests, length: length, version: version)
            end
          end

          attr_reader :length, :digests, :version

          def initialize(digests:, length:, version:)
            @digests = digests
            @length = length
            @version = version
          end

          private_class_method :new

          def check(content)
            digests.check(content)
          end
        end
      end
    end
  end
end
