# frozen_string_literal: true

if Gem.loaded_specs.key?("pimpmychangelog")
  require "pimpmychangelog"
else
  warn "'pimpmychangelog' gem not loaded: skipping tasks..." if Rake.verbose == true
  return
end

namespace :changelog do
  task :format do
    PimpMyChangelog::CLI.run!
  end
end
