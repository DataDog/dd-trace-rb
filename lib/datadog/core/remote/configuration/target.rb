# frozen_string_literal: true

require 'digest/sha2'
require_relative 'path'

module Datadog
  module Core
    module Remote
      class Configuration
        # TargetMap stores information regarding Configuration::Path and Configuration::Target
        class TargetMap < Hash
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
              length = Integer(hash['length'])
              digests = DigestList.parse(hash['hashes'])

              new(digests: digests, length: length)
            end
          end

          attr_reader :length, :digests

          def initialize(digests:, length:)
            @digests = digests
            @length = length
          end

          private_class_method :new

          def check(content)
            digests.check(content.data)
          end

          # Represent a list of Configuration::Target::Digest
          class DigestList < Array
            class << self
              def parse(hash)
                new.concat(hash.map { |type, hexdigest| Digest.new(type, hexdigest) })
              end
            end

            def check(data)
              map { |digest| digest.check(data) }.reduce(:&)
            end
          end

          private_constant :DigestList

          # Stores and validates different cryptographic hash functions
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
                raise
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

          private_constant :DigestList
        end
      end
    end
  end
end
