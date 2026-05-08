require 'fileutils'

namespace :rbs do
  desc 'Report sig/*.rbs files whose matching lib/*.rb no longer exists'
  task :stale do |_task, args|
    glob = args.to_a.map { |g| /\.rbs$/.match?(g) ? g : "#{g}/**/*.rbs" }
    glob = ['sig/**/*.rbs'] if glob.empty?

    stale = Dir[*glob].reject do |sig|
      next true if /^sig\/helpers\//.match?(sig)

      next if !/^sig\//.match?(sig)
      next if !/\.rbs$/.match?(sig)

      lib = sig.sub(/^sig/, 'lib').sub(/\.rbs$/, '.rb')

      File.exist?(lib)
    end

    stale.each { |sig| puts sig }

    if stale.any?
      warn <<-EOS
        +------------------------------------------------------------------------------+
        | **Hello there, fellow contributor who just triggered a type signature error**|
        |                                                                              |
        | It looks like you removed a file from `lib/` and this left a lingering       |
        | signature file in `sig/`. If this file is stale you can clean up             |
        | automatically with:                                                          |
        |                                                                              |
        |   bundle exec rake rbs:clean                                                 |
        |                                                                              |
        | But if you have moved or renamed a file in `lib`, please consider moving and |
        | updating corresponding signature in `sig`! See the following guide:          |
        |                                                                              |
        |   less docs/StaticTypingGuide.md                                             |
        |                                                                              |
        | Also, if this is too annoying for you -- let us know! We definitely are      |
        | still improving how we use the tool.                                         |
        +------------------------------------------------------------------------------+
      EOS

      exit 1
    end
  end

  desc 'Report lib/*.rb files with no matching sig/*.rbs (inline-checked files in Steepfile are exempt)'
  task :missing do |_task, args|
    glob = args.to_a.map { |g| /\.rb$/.match?(g) ? g : "#{g}/**/*.rb" }
    glob = ['lib/**/*.rb'] if glob.empty?

    # Files checked with inline RBS annotations (Steep 2.0+ `check ..., inline: true`
    # entries in the Steepfile) declare their types in the `.rb` file itself, so they
    # don't need a matching `sig/*.rbs`.
    inline_checked = File.read('Steepfile').scan(/check ['"](?<path>.+?)['"], inline: true/).flatten

    missing = Dir[*glob].reject do |lib|
      next if !/^lib\//.match?(lib)
      next if !/\.rb$/.match?(lib)
      next true if inline_checked.include?(lib)

      sig = lib.sub(/^lib/, 'sig').sub(/\.rb$/, '.rbs')

      File.exist?(sig)
    end

    missing.each { |lib| puts lib }

    if missing.any?
      warn <<-EOS
        +------------------------------------------------------------------------------+
        | **Hello there, fellow contributor who just triggered a type signature error**|
        |                                                                              |
        | It looks like you created a file in `lib/` that has no matching signature    |
        | file in `sig/`. You can automatically generate missing signature files with:
        |                                                                              |
        |   bundle exec rake rbs:prototype                                             |
        |                                                                              |
        | If at all possible, please try to change `untyped` items to the correct      |
        | types! See the following guide:                                              |
        |                                                                              |
        |   less docs/StaticTypingGuide.md                                             |
        |                                                                              |
        | Also, if this is too annoying for you -- let us know! We definitely are      |
        | still improving how we use the tool.                                         |
        +------------------------------------------------------------------------------+
      EOS

      exit 1
    end
  end

  desc 'Delete stale sig/*.rbs files whose matching lib/*.rb no longer exists'
  task :clean do |_task, args|
    glob = args.to_a.map { |g| /\.rbs$/.match?(g) ? g : "#{g}/**/*.rbs" }
    glob = ['sig/**/*.rbs'] if glob.empty?

    stale = Dir[*glob].reject do |sig|
      next if !/^sig\//.match?(sig)
      next if !/\.rbs$/.match?(sig)

      lib = sig.sub(/^sig/, 'lib').sub(/\.rbs$/, '.rb')

      File.exist?(lib)
    end

    stale.each do |sig|
      puts sig
      File.delete(sig)
    end

    # TODO: handle nested empty directories
    empty = Dir['sig/**/*'].select { |p| File.directory?(p) && (Dir.entries(p) - ['.', '..']).empty? }
    empty.each do |d|
      puts d
      Dir.rmdir(d)
    end
  end

  desc 'Generate sig/*.rbs stubs from lib/*.rb via `rbs prototype rb` (pass "force" to overwrite)'
  task :prototype do |_task, args|
    a = args.to_a

    force = a.shift if a.first == 'force'

    glob = a.map { |g| /\.rb$/.match?(g) ? g : "#{g}/**/*.rb" }
    glob = ['lib/**/*.rb'] if glob.empty?

    Dir[*glob].each do |lib|
      next if !/^lib\//.match?(lib)
      next if !/\.rb$/.match?(lib)

      sig = lib.sub(/^lib/, 'sig').sub(/\.rb$/, '.rbs')

      next if !force && File.exist?(sig)

      puts "#{lib} => #{sig}"

      rbs = `bundle exec rbs prototype rb '#{lib}'`

      if rbs.nil? || rbs.empty?
        warn "error: could not prototype '#{lib}'"
        exit 1
      end

      rbs.gsub!(/^\s*#.*?\n/m, '')

      FileUtils.mkdir_p(File.dirname(sig))
      File.open(sig, 'wb') { |f| f << rbs }
    end
  end
end
