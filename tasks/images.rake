namespace :images do
  desc "Pin ghcr.io/datadog/images-rb tags to a commit: rake images:pin[COMMIT_SHA]"
  task :pin, [:commit] do |_t, args|
    commit = args[:commit]
    abort "Usage: rake images:pin[COMMIT_SHA]" unless commit&.match?(/\A[0-9a-f]{40}\z/)

    pin = "-g#{commit}"
    files = `git grep -l ghcr.io/datadog/images-rb`.split("\n") - [__FILE__.delete_prefix("#{Dir.pwd}/")]

    files.each do |file|
      content = File.read(file)

      new_content = content.each_line.map do |line|
        next line unless line.include?("ghcr.io/datadog/images-rb/engines/")

        if line.match?(/-g[0-9a-f]{40}/)
          line.sub(/-g[0-9a-f]{40}/, pin)
        else
          line.sub(/(\S)(\s*)$/, "\\1#{pin}\\2")
        end
      end.join

      if new_content != content
        File.write(file, new_content)
        puts "Updated #{file}"
      end
    end
  end
end
