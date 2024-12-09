import json
import pandas as pd

input_file = 'minimum_gem_output.json'
with open(input_file, 'r') as file:
    data = json.load(file)

rows = []
for integration_name, versions in data.items():
    ruby_min, jruby_min = versions
    rows.append({"Integration": integration_name, "Ruby Min": ruby_min, "JRuby Min": jruby_min})

df = pd.DataFrame(rows)

output_file = 'integration_versions.md'

with open(output_file, 'w') as md_file:
    md_file.write("| Integration | Ruby Min | JRuby Min |\n")
    md_file.write("|-------------|-----------|----------|\n")
    for _, row in df.iterrows():
        md_file.write(f"| {row['Integration']} | {row['Ruby Min']} | {row['JRuby Min']} |\n")