require 'fileutils'

require 'rubygems'
# require 'rubygems/specification'
# spec = Gem::Specification.load 'Gemfile'
# puts spec

def all_gemsets
  @all_gemsets ||= Dir.glob('spec/**/gemset.rb')
end

class RemoteGemResolver
  require 'net/http'
  require 'net/http'
  require 'uri'

  require 'json'

  def initialize(name)
    @name = name
  end

  def raw_versions
    @raw_versions ||= JSON.parse(Net::HTTP.get(URI("https://rubygems.org//api/v1/versions/#{@name}.json")))
  end

  def version_numbers
    @all_versions ||= raw_versions.map{|v|Gem::Version.new(v['number'])}
  end

  def major_versions
    @major_versions ||= version_numbers.reverse.reduce({}) { |agg, v| agg[v.canonical_segments.first] = v; agg }.values
  end

  def self.for(name)
    @cache ||= {}
    @cache[name] ||= new(name)
  end
end

class DslParser
  def initialize
    @dependencies = []
    @rubies = []
  end

  def ruby(*versions)
    @rubies << versions
  end

  def gem(name, *versions, **options)
    @dependencies << Gem::Dependency.new(name, *versions)
  end

  def to_gemfiles
    files = []
    @dependencies.each do |dep|
      RemoteGemResolver.for(dep.name).major_versions.each do |v|
        lines = []
        lines << 'source "https://rubygems.org"'
        lines << "gem '#{dep.name}', '#{v.version}'"
        files << lines.join("\n")
      end
    end
    files
  end

  def to_s
    puts "@rubies: #{@rubies}"
    puts "@dependencies: #{@dependencies}"
  end

  def parse(gemset)
    instance_eval(gemset, __FILE__, __LINE__)
  end
end

require 'tempfile'
def resolve_for(gemset)
  Tempfile.create('gemset_for_bundler') do |file|
    path = file.path
    definition = Bundler::Definition.build(path, File.join("#{path}.lock"), false)
    definition.resolve_remotely!
    definition.resolve['dalli'].first.version
  end
end

all_gemsets.each do |gemset|

  parser = DslParser.new
  parser.parse(IO.read(gemset))
  puts parser.to_gemfiles
end
