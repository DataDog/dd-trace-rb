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

if (for_engine = ARGV[0]) && (for_version = ARGV[1])
  matrix.select! { |e| e[:engine][:name] == for_engine && e[:engine][:version] == for_version }
end

puts(JSON.dump({ include: matrix }))
