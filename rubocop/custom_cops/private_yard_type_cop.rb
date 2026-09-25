# frozen_string_literal: true

module CustomCops
  # Custom cop that rejects YARD type tags on private methods covered by RBS.
  #
  # Private method types belong in the mirrored `sig/` file. Duplicating them
  # in YARD comments creates a second source of truth that can drift from the
  # signature.
  #
  # @example
  #   # bad
  #   private
  #
  #   # @param value [String]
  #   # @return [Boolean]
  #   def valid?(value)
  #     !value.empty?
  #   end
  #
  #   # good
  #   private
  #
  #   def valid?(value)
  #     !value.empty?
  #   end
  class PrivateYardTypeCop < RuboCop::Cop::Base
    include RuboCop::Cop::VisibilityHelp

    PARAM_TYPE_TAG = /@param\b\s+(?:\[[^\]]+\](?:\s+\S+)?|\S+\s+\[[^\]]+\])/.freeze
    RETURN_TYPE_TAG = /@return\b\s+\[[^\]]+\]/.freeze
    PUBLIC_API_TAG = /@public_api\b/.freeze

    MSG = "Private method's `@param`/`@return` type restates the RBS signature in `%<path>s`. " \
          "Remove the type annotation from prose; the `.rbs` file is the source of truth for " \
          "non-public surfaces (see .agents/skills/write-comment/SKILL.md)."

    def on_def(node)
      return unless node_visibility(node) == :private

      rbs_path = matching_rbs_path
      return unless rbs_path && File.file?(rbs_path)

      comments = preceding_comment_block(node)
      return if comments.any? { |comment| comment.text.match?(PUBLIC_API_TAG) }

      comments.each do |comment|
        next unless yard_type_tag?(comment)

        add_offense(comment, message: format(MSG, path: rbs_path))
      end
    end

    private

    def matching_rbs_path
      source_path = processed_source.path
      return unless source_path

      repository_root = "#{File.expand_path(Dir.pwd)}#{File::SEPARATOR}"
      relative_path = File.expand_path(source_path).delete_prefix(repository_root)
      return unless relative_path.start_with?("lib/") && relative_path.end_with?(".rb")

      relative_path.sub(/\Alib\//, "sig/").sub(/\.rb\z/, ".rbs")
    end

    def preceding_comment_block(node)
      line = node.first_line - 1
      comments = []

      while line.positive?
        comment = processed_source.comment_at_line(line)
        break unless comment && standalone_comment?(comment)

        comments.unshift(comment)
        line -= 1
      end

      comments
    end

    def standalone_comment?(comment)
      processed_source.lines[comment.loc.line - 1].match?(/\A\s*#/)
    end

    def yard_type_tag?(comment)
      comment.text.match?(PARAM_TYPE_TAG) || comment.text.match?(RETURN_TYPE_TAG)
    end
  end
end
