require 'ddtrace/profiling/collectors/code_provenance'

RSpec.describe Datadog::Profiling::Collectors::CodeProvenance do
  it 'can emit json' do
    subject.refresh
    puts subject.generate_json
  end
end
