# frozen_string_literal: true

# Compile hooks into native binaries with Spinel.
#
# Examples:
#
#   Compile one hook (name, name.rb, or a path all resolve to the same hook)
#   ruby compile.rb require-skill
#
#   Compile every hook (all *.rb in this directory except compile.rb)
#   ruby compile.rb
#
# Requires `spinel` on PATH (https://github.com/matz/spinel).

require "fileutils"

OUTPUT_DIR = File.join(__dir__, "compiled")

def compile(source)
  output = File.join(OUTPUT_DIR, File.basename(source, ".rb"))
  FileUtils.mkdir_p(OUTPUT_DIR)

  system("spinel", source, "-o", output, exception: true)
rescue Errno::ENOENT
  abort "spinel not found on PATH (https://github.com/matz/spinel)"
end

sources =
  if ARGV.empty?
    Dir.glob(File.join(__dir__, "*.rb")) - [File.join(__dir__, "compile.rb")]
  else
    arg = ARGV[0]
    source = File.file?(arg) ? arg : File.join(__dir__, "#{File.basename(arg, ".rb")}.rb")
    abort "no such hook: #{arg} — pass a hook name (require-skill) or a path to its .rb" unless File.file?(source)

    [source]
  end

abort "no hooks to compile" if sources.empty?
sources.each { |source| compile(source) }
