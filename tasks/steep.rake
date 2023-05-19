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
          | stab at getting it to work; you'll find a guide under                        |
          | docs/StaticTypingGuide.md for how to use it.                                 |
          |                                                                              |
          | Feel free to unblock yourself by ignoring any files that triggered           |
          | issues by changing the `Steepfile` (you'll find a lot of ignores there       |
          | already).                                                                    |
          |                                                                              |
          | Also, if this is too annoying for you -- let us know! We definitely are      |
          | still improving how we use the tool.                                         |
          +------------------------------------------------------------------------------+
        EOS
        exit 1
      end
    end
  end
end

task :typecheck => :'steep:check'
