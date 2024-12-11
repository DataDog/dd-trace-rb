require 'json'

# Input and output file names
input_file = 'minimum_gem_output.json'
output_file = 'integration_versions.md'

# Read JSON data from the input file
data = JSON.parse(File.read(input_file))

# Prepare the Markdown content
comment = "# This is a table of supported integration versions generated from gemfiles."
header = "| Integration | Ruby Min | JRuby Min |\n"
separator = "|-------------|----------|-----------|\n"
rows = data.map do |integration_name, versions|
  ruby_min, jruby_min = versions
  "| #{integration_name} | #{ruby_min} | #{jruby_min} |"
end

# Write the Markdown file
File.open(output_file, 'w') do |file|
  file.puts comment
  file.puts header
  file.puts separator
  rows.each { |row| file.puts row }
end
