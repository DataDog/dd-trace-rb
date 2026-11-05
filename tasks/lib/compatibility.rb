# Sneakers requires Rake 12, which forwards FileUtils keywords as positional hashes.
if Gem::Version.new(Rake::VERSION) < Gem::Version.new("13.0") && Hash.respond_to?(:ruby2_keywords_hash)
  module RakeFileUtilsKeywords
    def rake_merge_option(args, defaults)
      super.tap do |merged|
        merged[-1] = Hash.ruby2_keywords_hash(merged.last)
      end
    end
  end

  Rake::FileUtilsExt.prepend(RakeFileUtilsKeywords)
end
