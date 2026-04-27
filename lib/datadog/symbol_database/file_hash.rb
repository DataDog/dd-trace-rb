# frozen_string_literal: true

require 'digest/sha1'

module Datadog
  module SymbolDatabase
    # Computes Git-style SHA-1 hashes of Ruby source files for backend commit inference.
    #
    # Uses Git's blob hash algorithm: SHA1("blob <size>\0<content>")
    # Hashes enable the backend to correlate runtime code with Git repository history,
    # identifying which commit is actually deployed.
    #
    # Called by: Extractor (when building MODULE scopes)
    # Stores result in: Scope's language_specifics[:file_hash]
    # Returns: 40-character hex string or nil if file unreadable
    #
    # @api private
    module FileHash
      module_function

      # Compute Git-style SHA-1 hash of a file.
      # Uses Git's blob hash algorithm: SHA1("blob <size>\0<content>")
      # Returns nil on any error (file not found, permission denied, etc.)
      #
      # @param file_path [String] Path to the file
      # @param logger [#debug] Logger for error reporting
      # @return [String, nil] 40-character hex-encoded SHA-1 hash, or nil if error
      def compute(file_path, logger:)
        return nil unless file_path
        return nil unless File.exist?(file_path)

        content = File.read(file_path, mode: 'rb')
        size = content.bytesize
        git_blob = "blob #{size}\0#{content}"

        # SHA-1 is required here to match Git's blob hash format for commit inference.
        # This is not a security vulnerability - we're computing file content hashes
        # to match against Git objects, not using SHA-1 for authentication/integrity.
        Digest::SHA1.hexdigest(git_blob)  # nosemgrep: ruby.lang.security.weak-hashes-sha1.weak-hashes-sha1
      rescue => e
        logger.debug { "symdb: file hash failed for #{file_path}: #{e.class}: #{e}" }
        nil
      end
    end
  end
end
