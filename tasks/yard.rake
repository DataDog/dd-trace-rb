
if Gem.loaded_specs["yard"]
  require 'yard'
else
  warn "'yard' gem not loaded: skipping tasks..." if Rake.verbose == true
  return
end

YARD::Rake::YardocTask.new(:docs) do |t|
  # Options defined in `.yardopts` are read first, then merged with
  # options defined here.
  #
  # It's recommended to define options in `.yardopts` instead of here,
  # as `.yardopts` can be read by external YARD tools, like the
  # hot-reload YARD server `yard server --reload`.

  t.options += ['--title', "datadog #{Datadog::VERSION::STRING} documentation"]
end
