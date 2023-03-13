# frozen_string_literal: true

require 'digest/sha2'

module Datadog
  module Core
    module Remote
      class Configuration
        class Target
          def initialize(digests:, length:)
            @digests = digests
            @length = length
          end

          def check(content)
            @digests.check(content.data)
          end

          class << self
            def parse(hash)
              length = Integer(hash['length'])
              digests = DigestList.parse(hash['hashes'])

              new(digests: digests, length: length)
            end
          end

          class Digest
            attr_reader :type, :hexdigest

            def initialize(type, hexdigest)
              @type = type.to_sym
              @hexdigest = hexdigest
            end

            def check(data)
              case @type
              when :sha256
                chunked_hexdigest(data) == hexdigest
              else
                fail
              end
            ensure
              data.rewind
            end

            private

            DIGEST_CHUNK = 1024

            def chunked_hexdigest(io)
              d = ::Digest::SHA256.new

              while (buf = io.read(DIGEST_CHUNK))
                d.update(buf)
              end

              d.hexdigest
            end
          end

          class DigestList < Array
            def check(data)
              map { |digest| digest.check(data) }.reduce(:&)
            end

            class << self
              def parse(hash)
                new.concat(hash.map { |type, hexdigest| Digest.new(type, hexdigest) })
              end
            end
          end
        end

        class TargetMap < Hash
          attr_reader :opaque_backend_state, :version

          def initialize
            super

            @opaque_backend_state = nil
            @version = nil
          end

          class << self
            def parse(hash)
              opaque_backend_state = hash['signed']['custom']['opaque_backend_state']
              version = hash['signed']['version']

              map = new

              map.instance_eval do
                @opaque_backend_state = opaque_backend_state
                @version = version
              end

              hash['signed']['targets'].each_with_object(map) do |(p, t), m|
                path = Configuration::Path.parse(p)
                target = Configuration::Target.parse(t)

                m[path] = target
              end
            end
          end
        end
      end
    end
  end
end
