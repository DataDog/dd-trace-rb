lib = File.expand_path('../../lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'datadog'

require 'yaml'

regenerate_todo = ARGV.include?('--regenerate-todo')
ignore_todo = ARGV.include?('--ignore-todo')

DOCS = File.read('docs/GettingStarted.md')

todos = if !regenerate_todo && !ignore_todo && File.exist?('.github/check_config_doc_todo.yml')
          YAML.safe_load(File.read('.github/check_config_doc_todo.yml'))
        else
          {
            'library' => [],
            'integrations' => Hash.new { |h, k| h[k] = [] }
          }
        end

total_todos = 0
total_oks = 0

def walk(config, path = nil, &block)
  config.to_h.each do |key, value|
    if value.is_a?(Datadog::Core::Configuration::Base)
      walk(value, "#{path}#{key}.", &block)
    else
      block.call("#{path}#{key}")
    end
  end
end

library_offences = []

walk(Datadog.configuration) do |full_name|
  if !DOCS.include?(full_name)
    total_todos += 1
    if regenerate_todo || !todos['library']&.include?(full_name)
      library_offences << full_name
    end
  else
    total_oks += 1
  end
end

integration_offences = Hash.new { |h, k| h[k] = [] }

Datadog::Tracing::Contrib::REGISTRY.to_h.each do |integration_name, _|
  config = Datadog.configuration.tracing[integration_name]
  walk(config) do |full_name|
    # Convert `_` in the integration name to any character or no character, as we have
    # different cases, e.g. DelayedJob, Action Cable.
    name_match = integration_name.to_s.gsub('_', '.?')

    matcher = Regexp.new('^### ' + name_match + '\s*\n(.*?)(?=^### |\z)', Regexp::IGNORECASE | Regexp::MULTILINE)

    section = DOCS[matcher, 1]
    if section
      if !section.include?(full_name)
        total_todos += 1
        if regenerate_todo || !todos['integrations'][integration_name.to_s]&.include?(full_name)
          integration_offences[integration_name.to_s] << full_name
        end
      else
        total_oks += 1
      end
    else
      total_todos += 1
      if regenerate_todo || !todos['integrations'][integration_name.to_s]&.include?('all')
        integration_offences[integration_name.to_s] = 'all'
      end
    end
  end
end

integration_offences_count = integration_offences.values.flatten.size
total_offences = library_offences.size + integration_offences_count

def green(str)
  "\e[32m#{str}\e[0m"
end

def yellow(str)
  "\e[33m#{str}\e[0m"
end

def print_library_offence_details(offences, search_dir, exclude_dir = '')
  offences.each do |offence|
    STDERR.puts "    • #{offence}"
    search_term = "option :#{offence.split('.')[-1]}"
    matches = `grep -nE --exclude-dir=#{exclude_dir} '^[^#]*#{search_term}' -R #{search_dir}`
    lines = matches.lines
    if lines.size == 1
      STDERR.puts "       #{lines[0].strip}"
    elsif lines.size > 1
      STDERR.puts "      Found in multiple places:"
      lines.each do |line|
        STDERR.puts "       #{line.strip}"
      end
    end
  end
end

puts green("😁 Total options documented: #{total_oks}") if total_oks > 0

puts yellow("🧐 Total offences ignored by TODOs: #{total_todos}") if !ignore_todo && !regenerate_todo && total_todos > 0

if regenerate_todo
  todos = {
    'library' => library_offences,
    'integrations' => integration_offences
  }
  File.write('.github/check_config_doc_todo.yml', todos.to_yaml)
  puts green("✒️ #{total_offences} total TODOs updated in .github/check_config_doc_todo.yml")
elsif total_offences > 0
  if library_offences.size > 0
    STDERR.puts "❗️Library configuration options not documented: #{library_offences.size}"
    print_library_offence_details(library_offences, "lib", "lib/datadog/tracing/contrib")
    STDERR.puts
    STDERR.puts "  Please document them in docs/GettingStarted.md, section `## Additional configuration`"
    STDERR.puts
  end

  if integration_offences_count > 0
    STDERR.puts "️️️❗️Integration configuration options not documented: #{integration_offences_count}"
    integration_offences.each do |integration, offences|
      if offences == 'all'
        STDERR.puts "  ▸ Integration '#{integration}'"
        STDERR.puts "    • Documentation section not found!"
      else
        STDERR.puts "  ▸ Integration '#{integration}'"
        print_library_offence_details(offences, "lib/datadog/tracing/contrib/#{integration}")
      end
    end
    STDERR.puts
    STDERR.puts "  Please document them in docs/GettingStarted.md, section `## Integration instrumentation`"
  end

  STDERR.puts
  STDERR.puts "😭 Total offences found: #{total_offences}"
  exit 1
end

