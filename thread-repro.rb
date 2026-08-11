depth = (ENV["REPRO_NEST_DEPTH"] || "20").to_i
attempts = (ENV["REPRO_ATTEMPTS"] || "5").to_i
locals = (0...depth).map { |i| "local_#{i}" }

def burn_cpu(seed)
  total = seed
  3_000.times { |x| total = (total * 31 + x) % 1_000_003 }
  total
end

attempts.times do |attempt|
  source = +""
  locals.each_with_index do |name, i|
    source << "  #{name} = \"frame-#{i}\"\n"
    source << "  [1].each do\n"
  end
  source << "    puts \"attempt #{attempt}: escaping now, depth=#{depth}\"\n"
  source << "    child = Thread.new { [#{locals.join(", ")}].join.length + burn_cpu(#{attempt}) }\n"
  source << "    child.join\n"
  source << "    puts \"attempt #{attempt}: escape complete\"\n"
  locals.size.times { source << "  end\n" }

  path = "/tmp/pure_escape_attempt_#{attempt}.rb"
  File.write(path, source)
  load(path)
end

puts "done, #{attempts} attempts"
