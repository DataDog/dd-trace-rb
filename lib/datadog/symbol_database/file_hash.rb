# frozen_string_literal: true

require 'digest/sha1'

module Datadog
  module SymbolDatabase
    # Computes Git-style SHA-1 hashes of source files for commit inference
    module FileHash
      module_function

      # Compute Git-style SHA-1 hash of a file
      # Uses Git's blob hash algorithm: SHA1("blob <size>\0<content>")
      #
      # @param file_path [String] Path to the file
      # @return [String, nil] Hex-encoded SHA-1 hash, or nil if error
      def compute(file_path)
        return nil unless file_path
        return nil unless File.exist?(file_path)

        content = File.read(file_path, mode: 'rb')
        size = content.bytesize
        git_blob = "blob #{size}\0#{content}"

        Digest::SHA1.hexdigest(git_blob)
      rescue => e
        Datadog.logger.debug("SymDB: File hash computation failed for #{file_path}: #{e.message}")
        nil
      end
    end
  end
end
