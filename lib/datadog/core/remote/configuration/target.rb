# frozen_string_literal: true

require_relative "path"
require_relative "digest"

module Datadog
  module Core
    module Remote
      class Configuration
        # TargetMap stores information regarding Configuration::Path and Configuration::Target
        class TargetMap < Hash
          class << self
            def parse(hash)
              signed = hash.fetch("signed")
              raise TypeError, "Invalid type for signed: expected Hash: #{signed.inspect}" unless signed.is_a?(Hash)

              # Note that the +dig+ call permits +hash['signed']+ to be
              # missing the +custom+ subtree entirely.
              # Previously the subtree was required but +opaque_backend_state+
              # could still be missing (and obtained here as nil).
              opaque_backend_state = signed.dig("custom", "opaque_backend_state")
              opaque_backend_state = opaque_backend_state.is_a?(String) ? opaque_backend_state : nil
              # The version appears to be optional to the rest of this class,
              # and we have tests that do not provide it.
              version = signed["version"]
              version = version.is_a?(Integer) ? version : nil

              map = new

              map.instance_eval do
                @opaque_backend_state = opaque_backend_state
                @version = version
              end

              targets = signed.fetch("targets")
              raise TypeError, "Invalid type for targets: expected Hash: #{targets.inspect}" unless targets.is_a?(Hash)

              targets.each_with_object(map) do |(p, t), m|
                path = Configuration::Path.parse(p)
                raise TypeError, "Invalid type for targets entry: expected Hash: #{t.inspect}" unless t.is_a?(Hash)
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
              length = hash.fetch("length")
              raise TypeError, "Invalid type for length: expected Integer: #{length.inspect}" unless length.is_a?(Integer)

              hashes = hash.fetch("hashes")
              raise TypeError, "Invalid type for hashes: expected Hash: #{hashes.inspect}" unless hashes.is_a?(Hash)
              digests = Configuration::DigestList.parse(hashes)

              version = hash.dig("custom", "v")
              raise TypeError, "Invalid type for custom.v: expected Integer: #{version.inspect}" unless version.is_a?(Integer)

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
