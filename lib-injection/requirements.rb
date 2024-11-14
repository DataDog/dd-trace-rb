#!/usr/bin/env ruby

require 'json'

def requirements
  reqs = {
    '$schema' => 'https://raw.githubusercontent.com/DataDog/auto_inject/refs/heads/main/preload_go/cmd/library_requirements_tester/testdata/requirements_schema.json',
    'version' => 1,
    'native_deps' => {
      'glibc' => [
        {
          'arch' => 'x64',
          'supported' => true,
          'min' => '2.27',
          'description' => 'libffi needs memfd_create',
        },
        {
          'arch' => 'arm64',
          'supported' => true,
          'min' => '2.27',
          'description' => 'libffi needs memfd_create',
        },
      ],
      'musl' => [
        {
          'arch' => 'x64',
          'supported' => false,
          'description' => 'no musl build',
        },
        {
          'arch' => 'arm64',
          'supported' => false,
          'description' => 'no musl build',
        },
      ],
    },
    'deny' => [],
  }

  # gem command such as install aren't quite usuful to inject into
  # plus there are issues when it ends up calling gcc
  reqs['deny'] << {
    'id' => 'gem',
    'description' => 'Ignore the rubygems CLI',
    'os' => nil,
    'cmds' => [
      '**/ruby'
    ],
    'args' => [{ 'args' => ['*/gem'], 'position' => 1 }],
    'envars' => nil,
  }

  reqs['deny'] << {
    'id' => 'ruby_disable_gems',
    'description' => 'Rubygems is required for injection to function',
    'os' => nil,
    'cmds' => [
      '**/ruby'
    ],
    'args' => [{ 'args' => ['--disable-gems'], 'position' => nil }],
    'envars' => nil,
  }

  # Prevent endless reexecution when RUBYOPTS is forcefully set
  # Command: {"Path":"/usr/local/bin/ruby","Args":["/usr/local/bin/ruby","--disable-gems","setup.rb","--no-document","--previous-version","3.3.26"]}
  # See: https://github.com/rubygems/rubygems/blob/90c90addee4bda3130cf44f1321eebf162367d1b/setup.rb#L13-L20
  reqs['deny'] << {
    'id' => 'gem_update_system',
    'description' => 'Ignore the rubygems update setup.rb',
    'os' => nil,
    'cmds' => [
      '**/ruby'
    ],
    'args' => [{ 'args' => ['setup.rb'], 'position' => nil }],
    'envars' => nil,
  }

  # `bundle exec` is the only command we want to inject into.
  # there is no `allow` overriding `deny` so we're left to exclude all of the
  # possible others.
  %w[bundle bundler].each do |exe|
    %w[
      install
      update
      cache
      config
      help
      add
      binstubs
      check
      show
      outdated
      console
      open
      lock
      viz
      init
      gem
      platform
      clean
      doctor
      remove
      plugin
      version
    ].each do |command|
      [[], ['*'], ['*', '*'], ['*', '*', '*'], ['*', '*', '*', '*']].each do |varargs|
        reqs['deny'] << {
          'id' => "#{exe}_#{command}",
          'description' => "Ignore #{exe} #{command}",
          'os' => nil,
          'cmds' => [
            '**/ruby'
          ],
          'args' => [{ 'args' => ["*/#{exe}", *varargs, command], 'position' => 1 }],
          'envars' => nil,
        }
      end
    end
  end

  # ruby executables we don't want to inject into
  %w[
    ri
    rdoc
    racc
    erb
    rdbg
    rbs
    typeprof
  ].each do |exe|
    reqs['deny'] << {
      'id' => "ruby_#{exe}",
      'description' => "Ignore ruby's #{exe}",
      'os' => nil,
      'cmds' => [
        '**/ruby'
      ],
      'args' => [{ 'args' => ["**/#{exe}"], 'position' => 1 }],
      'envars' => nil,
    }
  end

  # we don't want to mess with chef
  %w[
    chef
    chef-apply
    chef-client
    chef-resource-inspector
    chef-service-manager
    chef-shell
    chef-solo
    chef-windows-service
    knife
  ].each do |exe|
    reqs['deny'] << {
      'id' => "chef_#{exe.tr('-', '_')}",
      'description' => "Ignore chef's #{exe}",
      'os' => nil,
      'cmds' => [
        '**/ruby'
      ],
      'args' => [{ 'args' => ["*/#{exe}"], 'position' => 1 }],
      'envars' => nil,
    }
  end

  # we don't want to mess with omnibus
  %w[
    omnibus
    kitchen
  ].each do |exe|
    reqs['deny'] << {
      'id' => "omnibus_#{exe}",
      'description' => "Ignore omnibus's #{exe}",
      'os' => nil,
      'cmds' => [
        '**/ruby'
      ],
      'args' => [{ 'args' => ["*/#{exe}"], 'position' => 1 }],
      'envars' => nil,
    }
  end

  # we don't want to mess with appraisal but appraisal can execute, like bundler
  %w[
    clean
    generate
    help
    install
    list
    update
    version
  ].each do |command|
    reqs['deny'] << {
      'id' => "appraisal_#{command}",
      'description' => "Ignore appraisal #{command}",
      'os' => nil,
      'cmds' => [
        '**/ruby'
      ],
      'args' => [{ 'args' => ['*/appraisal', command], 'position' => 1 }],
      'envars' => nil,
    }
  end

  %w[
    vagrant
  ].each do |exe|
    reqs['deny'] << {
      'id' => "vagrant_#{exe}",
      'description' => "Ignore vagrant's #{exe}",
      'os' => nil,
      'cmds' => [
        '**/ruby'
      ],
      'args' => [{ 'args' => ["*/#{exe}"], 'position' => 1 }],
      'envars' => nil,
    }
  end

  %w[
    puppet
  ].each do |exe|
    reqs['deny'] << {
      'id' => "puppet_#{exe}",
      'description' => "Ignore puppet's #{exe}",
      'os' => nil,
      'cmds' => [
        '**/ruby'
      ],
      'args' => [{ 'args' => ["*/#{exe}"], 'position' => 1 }],
      'envars' => nil,
    }
  end

  # yes, there's a `brew` beyond macOS
  %w[
    brew
  ].each do |exe|
    reqs['deny'] << {
      'id' => "homebrew_#{exe}",
      'description' => "Ignore Homebrew's #{exe}",
      'os' => nil,
      'cmds' => [
        '**/ruby'
      ],
      'args' => [{ 'args' => ["*/#{exe}"], 'position' => 1 }],
      'envars' => nil,
    }
  end

  reqs
end

def write(path)
  File.binwrite(path, JSON.pretty_generate(requirements))
end

if $PROGRAM_NAME == __FILE__
  write(File.join(__dir__, 'requirements.json'))
end
