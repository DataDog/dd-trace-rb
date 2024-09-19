# Modern pry versions don't auto-require plugins, so let's try to load whatever we can
%w[pry-byebug pry-stack_explorer pry-nav pry-debugger-jruby].each do |extension|
  begin; require extension; rescue LoadError; nil end
end
