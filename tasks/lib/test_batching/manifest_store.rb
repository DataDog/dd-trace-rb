# frozen_string_literal: true

require "json"
require_relative "timing_files"
require_relative "weights"

# Filesystem adapter: reads and writes the aggregated weights manifest that
# the scheduled Update Task Weights workflow publishes and the batch job
# consumes.
module TestBatching
  module ManifestStore
    MANIFEST_PATH = "tmp/ci_task_timings.json"

    module_function

    # Aggregates every timing document in a directory into the manifest at
    # MANIFEST_PATH. Raises when the directory holds no timing files so the
    # scheduled workflow fails loudly instead of publishing empty weights.
    def update_from(directory)
      batch_timings = TimingFiles.read_all(directory)
      raise "no timing files found in #{directory}" if batch_timings.empty?

      write(Weights.from(batch_timings))
    end

    def write(weights, path: MANIFEST_PATH)
      File.write(path, JSON.pretty_generate(weights.to_h) + "\n")
    end
    private_class_method :write

    # Returns Weights::Missing when no readable manifest exists, so callers
    # can keep batching statically until the cache bootstraps.
    def load(path: MANIFEST_PATH)
      Weights.new(JSON.parse(File.read(path)))
    rescue Errno::ENOENT, JSON::ParserError => e
      warn "Could not read the weights manifest at #{path} (#{e.class}: #{e.message}); continuing without one"

      Weights::Missing.new
    end
  end
end
