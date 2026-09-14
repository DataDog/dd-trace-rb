# frozen_string_literal: true

require "json"
require_relative "../release_prep"
require_relative "fragment"

module ReleasePrep
  # The scaffold `rake unreleased:new` writes: placeholder values that teach
  # the field they sit in. The scaffold fails lint by design — the errors
  # name what each field still needs, and a committed placeholder cannot
  # pass CI.
  class FragmentTemplate
    FILENAME_FORMAT = "%Y%m%d%H%M%S.json"

    class << self
      # Writes a timestamp-named fragment into `dir` and returns its path.
      # The renderer ignores the filename; only the fields are read.
      def write(dir:)
        path = File.join(dir, Time.now.utc.strftime(FILENAME_FORMAT))
        File.write(path, JSON.pretty_generate(content) + "\n")

        path
      end

      # The placeholder entry, built from the validator's own constants so
      # the type and product lists cannot go stale. The message carries the
      # drafting rules plus a `#1234` reference that keeps lint red until
      # it is rewritten.
      def content
        {
          "type" => Fragment::TYPES.join(" | "),
          "product" => Fragment::PRODUCTS.join(" | "),
          "pull_request" => "#{REPO_URL}/pull/NNNN",
          "message" => "Fix <symptom> when <trigger>, or add <capability> via <access point>. " \
            "Identifiers in `code spans`; no #1234 references — the PR number renders automatically. " \
            "Conventions: unreleased/README.md; examples: unreleased/examples/.",
        }
      end
    end
  end
end
