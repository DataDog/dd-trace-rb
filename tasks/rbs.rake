require 'fileutils'

namespace :rbs do  # rubocop:disable Metrics/BlockLength
  task :stale do |_task, args|
    glob = args.to_a.map { |g| g =~ /\.rbs$/ ? g : "#{g}/**/*.rbs" }
    glob = ['sig/**/*.rbs'] if glob.empty?

    stale = Dir[*glob].reject do |sig|
      next if sig !~ /^sig\// # rubocop:disable Style/RegexpLiteral
      next if sig !~ /\.rbs$/

      lib = sig.sub(/^sig/, 'lib').sub(/\.rbs$/, '.rb')

      File.exist?(lib)
    end

    stale.each { |sig| puts sig }

    exit 1 if stale.any?
  end

  task :missing do |_task, args|
    glob = args.to_a.map { |g| g =~ /\.rb$/ ? g : "#{g}/**/*.rb" }
    glob = ['lib/**/*.rb'] if glob.empty?

    missing = Dir[*glob].reject do |lib|
      next if lib !~ /^lib\// # rubocop:disable Style/RegexpLiteral
      next if lib !~ /\.rb$/

      sig = lib.sub(/^lib/, 'sig').sub(/\.rb$/, '.rbs')

      File.exist?(sig)
    end

    missing.each { |lib| puts lib }

    exit 1 if missing.any?
  end

  task :clean do |_task, args|
    glob = args.to_a.map { |g| g =~ /\.rbs$/ ? g : "#{g}/**/*.rbs" }
    glob = ['sig/**/*.rbs'] if glob.empty?

    stale = Dir[*glob].reject do |sig|
      next if sig !~ /^sig\// # rubocop:disable Style/RegexpLiteral
      next if sig !~ /\.rbs$/

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

  task :prototype do |_task, args|
    a = args.to_a

    force = a.shift if a.first == 'force'

    glob = a.map { |g| g =~ /\.rb$/ ? g : "#{g}/**/*.rb" }
    glob = ['lib/**/*.rb'] if glob.empty?

    Dir[*glob].each do |lib|
      next if lib !~ /^lib\// # rubocop:disable Style/RegexpLiteral
      next if lib !~ /\.rb$/

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
