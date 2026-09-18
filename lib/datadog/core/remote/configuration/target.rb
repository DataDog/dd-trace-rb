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
              raise TypeError, "signed must be a Hash, got #{signed.class}" unless signed.is_a?(Hash)

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
              raise TypeError, "targets must be a Hash, got #{targets.class}" unless targets.is_a?(Hash)

              targets.each_with_object(map) do |(p, t), m|
                path = Configuration::Path.parse(p)
                raise TypeError, "target must be a Hash, got #{t.class}" unless t.is_a?(Hash)
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
              length = Integer(hash.fetch("length"))
              raise TypeError, "target length is required" unless length.is_a?(Integer)

              hashes = hash.fetch("hashes")
              raise TypeError, "hashes must be a Hash, got #{hashes.class}" unless hashes.is_a?(Hash)
              digests = Configuration::DigestList.parse(hashes)

              version = Integer(hash.dig("custom", "v"))
              raise TypeError, "target version (custom.v) is required" unless version.is_a?(Integer)

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
