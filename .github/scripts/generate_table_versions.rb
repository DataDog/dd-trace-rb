require 'json'

input_file = 'gem_output.json'
output_file = 'integration_versions.md'

data = JSON.parse(File.read(input_file))

comment = "# Integrations\n\n"
header = "| Integration | Ruby Min |  Ruby Max | JRuby Min | JRuby Max |\n"
separator = "|-------------|----------|-----------|----------|----------|\n"
rows = data.map do |integration_name, versions|
    ruby_min, ruby_max, jruby_min, jruby_max = versions.map { |v| v || "None" }
    "| #{integration_name} | #{ruby_min} | #{ruby_max} | #{jruby_min} | #{jruby_max} |"
end

File.open(output_file, 'w') do |file|
  file.puts comment
  file.puts header
  file.puts separator
  rows.each { |row| file.puts row }
end
