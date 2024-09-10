require 'pathname'
require 'erb'

load 'matrix.rb'


class Workflow
  PATH = Pathname.pwd / '.github' / 'workflows'
  TMPL_EXT = '.yml.erb'

  def initialize(name)
    @name = name
  end

  def matrix
    Matrix.new
  end

  def render
    erb.run(binding)
  end

  def erb
    ERB.new(template, trim_mode: "%<>")
  end

  def template
    File.read(PATH / (@name + TMPL_EXT))
  end
end


w = Workflow.new('unit-test')
$stdout.write w.render
