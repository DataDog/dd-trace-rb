namespace :steep do
  desc 'Runs the Steep type checker on the codebase'
  task :check do |_task, args|
    if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
      warn 'Sorry, cannot run Steep type checker on older rubies :('
    else
      args_sh = args.to_a.map { |a| "'#{a}'" }.join(' ')

      begin
        sh "steep check #{args_sh}".strip
      rescue
        warn <<-EOS
          +------------------------------------------------------------------------------+
          |  **Hello there, fellow contributor who just triggered a Steep type error**   |
          |                                                                              |
          | We're still experimenting with Steep on this codebase. If possible, take a   |
          | stab at getting it to work; you'll find a guide for how to use it here:      |
          |                                                                              |
          |   less docs/StaticTypingGuide.md                                             |
          |                                                                              |
          | Feel free to unblock yourself by adding a line per file that triggered       |
          | errors to the `Steepfile`:                                                   |
          |                                                                              |
          |   ignore 'lib/path/to/failing/file.rb'                                       |
          |                                                                              |
          | Also, if this is too annoying for you -- let us know! We definitely are      |
          | still improving how we use the tool.                                         |
          +------------------------------------------------------------------------------+
        EOS
        exit 1
      end
    end
  end

  task :stats do |_task, args|
    format = args.to_a.first || 'table'

    if format == 'md'
      data = `steep stats --format=csv`

      require 'csv'

      csv = CSV.new(data, headers: true)
      headers = true
      csv.each do |row|
        hrow = row.to_h

        if headers
          $stdout.write('|')
          $stdout.write(hrow.keys.join('|'))
          $stdout.write('|')
          $stdout.write("\n")

          $stdout.write('|')
          $stdout.write(hrow.values.map { |v| v =~ /^\d+$/ ? '--:' : ':--' }.join('|'))
          $stdout.write('|')
          $stdout.write("\n")
        end

        headers = false

        $stdout.write('|')
        $stdout.write(hrow.values.join('|'))
        $stdout.write('|')
        $stdout.write("\n")
      end

      # Append ignored files from Steepfile to the end of the steep/typecheck summary
      File
        .foreach('Steepfile')
        .with_object([]) { |line, ignored_files| line =~ /^\s*ignore\s+(["'])(.*?(?:\\?.)*?)\1/ && ignored_files << $2 }
        .each do |file|
          if File.exist?(file)
            $stdout.write("|datadog|#{file}|ignored|N/A|N/A|N/A|0|\n")
          else
            warn "Ignored file '#{file}' does not exist. Please remove it from the Steepfile."
          end
        end
    else
      sh "steep stats --format=#{format}"
    end
  end
end

task :typecheck => :'steep:check'
