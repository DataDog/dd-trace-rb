# frozen_string_literal: true

require 'digest'

module Datadog
  module Core
    module Remote
      class Configuration
        # Represent a list of Configuration::Digest
        class DigestList < Array
          class << self
            def parse(hash)
              new.concat(hash.map { |type, hexdigest| Digest.new(type, hexdigest) })
            end
          end

          def check(content)
            map { |digest| digest.check(content) }.reduce(:&)
          end
        end

        # Stores and validates different cryptographic hash functions
        class Digest
          class InvalidHashTypeError < StandardError; end
          attr_reader :type, :hexdigest

          class << self
            def hexdigest(type, data)
              unless String === data
                # This class (Digest) passes +data+ to the Ruby standard
                # library Digest routines without validating its type.
                # The stdlib Digest requires a String, and the previous
                # implementation of this class that used StringIO
                # unconditionally read from +data+ without validating the
                # type. Meaning, passing +nil+ as +data+ has never worked.
                # It still doesn't work in the present implementation.
                # Flag the nil data now to get earlier diagnostics when
                # developing tests for example.
                raise ArgumentError, "Invalid type for data: #{data.class}: expected String"
              end

              d = case type
              when :sha256
                ::Digest::SHA256.new
              when :sha512
                ::Digest::SHA512.new
              else
                raise InvalidHashTypeError, type
              end

              d.update(data)

              d.hexdigest
            end
          end

          def initialize(type, hexdigest)
            @type = type.to_sym
            @hexdigest = hexdigest
          end

          def check(content)
            content.hexdigest(@type) == hexdigest
          end
        end
      end
    end
  end
end
