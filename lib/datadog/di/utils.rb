# frozen_string_literal: true

module Datadog
  module DI
    module Utils
      # Returns whether the provided +path+ matches the user-designated
      # file suffix (of a line probe).
      #
      # If suffix is an absolute path (i.e., it starts with a slash), the path
      # must be identical for it to match.
      #
      # If suffix is not an absolute path, the path matches if its suffix is
      # the provided suffix, at a path component boundary.
      module_function def path_matches_suffix?(path, suffix)
        if path.nil?
          raise ArgumentError, "nil path passed"
        end
        if suffix.nil?
          raise ArgumentError, "nil suffix passed"
        end

        if suffix.start_with?('/')
          path == suffix
        else
          # Exact match is not possible here, meaning any matching path
          # has to be longer than the suffix. Require full component matches,
          # meaning either the first character of the suffix is a slash
          # or the previous character in the path is a slash.
          # For now only check for forward slashes for Unix-like OSes;
          # backslash is a legitimate character of a file name in Unix
          # therefore simply permitting forward or back slash is not
          # sufficient, we need to perform an OS check to know which
          # path separator to use.
          !!
          if path.length > suffix.length && path.end_with?(suffix)
            previous_char = path[path.length - suffix.length - 1]
            previous_char == "/" || suffix[0] == "/"
          end

          # Alternative implementation using a regular expression:
          # !!(path =~ %r,(/|\A)#{Regexp.quote(suffix)}\z,)
        end
      end
    end
  end
end
