# frozen_string_literal: true

require 'find'

namespace :lint do
  task all: [:frozen_string_literal]

  # standard-rb does not enable the Style/FrozenStringLiteralComment cop.
  # As we will still support Rubies < 3.4 for years, we need to check that all .rb files in lib folder start with frozen_string_literal: true.
  desc 'Check that all .rb files in lib folder start with frozen_string_literal: true'
  task :frozen_string_literal do
    files_without_magic_comment = []

    Find.find('lib') do |path|
      # Skip vendor folders
      Find.prune if File.basename(path) == 'vendor'

      next unless File.file?(path) && path.end_with?('.rb')

      # Skip binary files and symlinks
      next unless File.readable?(path) && !File.symlink?(path)

      begin
        first_line = File.open(path, 'r') { |f| f.gets&.strip }
        files_without_magic_comment << path unless first_line == '# frozen_string_literal: true'
      rescue => e
        puts "Warning: Could not read file #{path}: #{e.message}"
      end
    end

    if files_without_magic_comment.empty?
      puts "✅ All .rb files in lib folder have the '# frozen_string_literal: true' magic comment"
    else
      puts "❌ The first line of the following .rb files should be '# frozen_string_literal: true':"
      files_without_magic_comment.each { |file| puts "  - #{file}" }
      exit 1
    end
  end
end
