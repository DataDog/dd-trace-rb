# frozen_string_literal: true

module CustomCops
  # Prevents new OpenFeature type-checker suppressions from replacing accurate RBS.
  class OpenFeatureSteepIgnoreCop < RuboCop::Cop::Base
    DIRECTIVE = 'steep:ignore'
    MSG = 'Do not suppress OpenFeature type errors with `steep:ignore`; model the type in RBS instead.'

    def on_new_investigation
      processed_source.comments.each do |comment|
        offset = comment.text.index(DIRECTIVE)
        next unless offset
        next if allowed_comments.include?(allowed_comment_key(comment))

        begin_pos = comment.loc.expression.begin_pos + offset
        range = Parser::Source::Range.new(
          processed_source.buffer,
          begin_pos,
          begin_pos + DIRECTIVE.length
        )
        add_offense(range, message: MSG)
      end
    end

    private

    def allowed_comment_key(comment)
      "#{relative_file_path}:#{comment.text}"
    end

    def relative_file_path
      path = processed_source.file_path.tr('\\', '/')
      root = Dir.pwd.tr('\\', '/') + '/'
      path.start_with?(root) ? path.delete_prefix(root) : path
    end

    def allowed_comments
      Array(cop_config['AllowedComments'])
    end
  end
end
