require 'yaml'
require 'json'

map = eval(File.open('Matrixfile', 'r:UTF-8').read)
ruby_to_jruby = {
  '2.5' => ['9.2'],
  '2.6' => ['9.3'],
  '3.1' => ['9.4'],
}

definitions = map.each_with_object({}) do |(spec, appraisals), h|
  h[spec] = appraisals.each_with_object({}) do |(group, rubies), h2|
    ruby = rubies.scan(/✅ (\S+)/).flatten

    has_jruby = ruby.delete('jruby')

    engines = { 'ruby' => ruby }

    if has_jruby && (versions = ruby_to_jruby.select { |r, _| ruby.include?(r) }.values.flatten).any?
      engines['jruby'] = versions
    end

    h2[group] = engines
  end
end

# Rails 4.x is not supported on JRuby 9.2 (which is RUBY_VERSION 2.5)
definitions.each { |_, appraisals| appraisals.each { |appraisal, engines| appraisal =~ /^rails4/ && engines.key?('jruby') && engines['jruby'].delete('9.2') } }

matrix = definitions.each_with_object([]) do |(spec, appraisals), a|
  appraisals.each do |appraisal, engines|
    engines.each do |engine, versions|
      versions.each do |version|
        a << {
          spec: {
            task: spec,
            appraisal: appraisal,
          },
          engine: {
            name: engine,
            version: version
          }
        }
      end
    end
  end
end

selected_engine_name = nil
selected_engine_version = nil
selected_spec_task = nil
selected_spec_appraisal = nil
ARGV.each do |arg|
  case arg
  when /^engine.name:(\S+)/ then selected_engine_name = $1
  when /^engine.version:(\S+)/ then selected_engine_version = $1
  when /^spec.task:(\S+)/ then selected_spec_task = $1
  when /^spec.appraisal:(\S+)/ then selected_spec_appraisal = $1
  end
end

if selected_engine_name
  matrix.select! { |e| e[:engine][:name] == selected_engine_name }
end

if selected_engine_version
  matrix.select! { |e| e[:engine][:version] == selected_engine_version }
end

if selected_spec_task
  matrix.select! { |e| e[:spec][:task] == selected_spec_task }
end

if selected_spec_appraisal
  matrix.select! { |e| e[:spec][:appraisal] == selected_spec_appraisal }
end

puts(JSON.dump({ include: matrix }))
