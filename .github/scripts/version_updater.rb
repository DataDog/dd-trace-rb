require 'rubygems'
require 'bundler'
require 'bundler/cli'


# Run bundler and handle errors
def run_bundler_command(gemfile, command_args)
    Bundler.reset!
    ENV['BUNDLE_GEMFILE'] = gemfile
    Bundler::CLI.start(command_args)
rescue StandardError => e
    puts "Error: #{e.message}"
end

# Update a gem in all its gemfiles
def update_gem(gem_to_update, gems_in)
    # HACK - setting this to grpc while testing out the script
    # gem_to_update = 'grpc'
    gems_in[gem_to_update].each do |gemfile, version|
        puts "Checking to see if #{gem_to_update} needs to be updated in #{gemfile}"
        gemfile_lock = "#{gemfile}.lock"
        definition = Bundler::Definition.build(gemfile, gemfile_lock, nil)
        dependencies = definition.dependencies

        dependencies.each do |dep|
            next if gem_to_update != dep.name # only update the gem we chose at random
            # puts "Skipping #{dep.name} as it is not #{gem_to_update}"
            
            gem_name = dep.name
            gem_version = dep.requirements_list
            gem_requirements = Gem::Requirement.create(*gem_version)
            gem_platforms = dep.platforms
    
            puts "Gem Name: #{gem_name}"
            puts "Gem Version: #{gem_version}"
            puts "Gem Requirments: #{gem_requirements}"
            puts "Gem Platforms: #{gem_platforms}"
    
            latest = Gem.latest_version_for(gem_name)
    
            if gem_requirements.satisfied_by?(latest)
                puts "The latest (#{latest}) of #{gem_name} is satisfied by #{gem_requirements}"
                bundler_args = ['lock', '--update', gem_name]

                # do we have any platforms specified? If so, add them each with --add-platform
                bundler_args.concat(dep.platforms.map { |platform| ['--add-platform', platform.to_s] }) if dep.platforms.any?

                # NOTE: I'm seeing some platforms being removed
                # For example gemfiles/ruby_2.5_contrib.gemfile.lock has "grpc (1.48.0-x86_64-linux)"
                # But this platform isn't specified in the gemfile
                # Run the command here removes this "grpc (1.48.0-x86_64-linux)" instance entirely
                # TODO check with Marco/Tony/David for how this came to be as the PR they were added in was a while back and was just an update

                puts "Updating #{gem_name} with: #{bundler_args}"
                run_bundler_command(gemfile, bundler_args)
            else
                puts "The latest (#{latest}) of #{gem_name} is NOT satisfied by #{gem_requirements}"
                # TODO - should we attempt to do a --conservative update here?
            end
        end
    end
end


def parse_paths(paths, versions, gems_in)
    paths.each do |path|
        parser = Bundler::LockfileParser.new(Bundler.read_file(path))
        parser.specs.each do |spec|
            if versions[spec.name]
                 # "Gemfile.lock" -> "Gemfile"
                gem_file = path.sub(/\.lock$/, '')
                # gems_in['grpc'].Add([Gemfile, 1.0.0])
                gems_in[spec.name] << [gem_file, spec.version]
                # keep track of the highest vesion seen - TODO likley redunant now and replaced by "gems_in"
                versions[spec.name] = [versions[spec.name], spec.version].max
            else # The gem doesn't appear to be an integration - likely a dependency of one though - skip it
                # puts "Skipping #{spec.name} as it isn't in contrib"
            end
        end
    end
end

def run_update
    # for each directory in /contrib/ read the hash of the loaded Gems
    # https://www.rubydoc.info/github/rubygems/rubygems/Gem.loaded_specs
    # taken from: https://github.com/DataDog/apm-shared-github-actions/blob/2b49e71feba54bdfaabdeeb026ec3032d819371f/.github/scripts/get-tested-integration-versions.rb#L36
    ddtrace_specs = `grep -Rho 'Gem.loaded_specs.*' ../lib/datadog/tracing/contrib/`
    integrated_gems = ddtrace_specs.split.map { |m| m.match(/Gem.loaded_specs\[.([^\]]+).\]/)&.[](1) }.uniq.compact

    # populate each found integration with a dummy version of "0.0.0"
    versions = {}
    integrated_gems.each do |integrated|
        versions[integrated] = Gem::Version.new('0.0.0')
    end

    # keep track of each integration and a list of their gemfiles that they are in
    gems_in = Hash.new {|hash, key| hash[key] = [] }
    # "grpc"=>[["../gemfiles/ruby_2.5_contrib.gemfile", #<Gem::Version "1.48.0">], ["../gemfiles/ruby_2.6_contrib.gemfile", #<Gem::Version "1.48.0">]

    versions.each do |name, version|
        puts "#{name}: #{version}"
    end

    paths = Dir['../gemfiles/jruby_*.lock', '../gemfiles/ruby_*.lock']
    
    # TODO - a lock file can contain the same gem multiple times
    # for example: grpc (1.66.0), grpc (1.66.0-aarch64-linux), and grpc (1.66.0-x86_64-linux)
    # are all "grpc", but each one is "different", so the same gemfile in this loop gets added multiple times
    # should probably fix this
    parse_paths(paths, versions, gems_in)
    # TODO - could we look through open PR titles to rule out which gems to update?
    #        if the PR is the autogenerated PR to update the gem we could skip it
    gem_to_update = integrated_gems.sample # HACKY pick a random gem to attempt to update
    puts "Randomly chose #{gem_to_update} to update"
    update_gem(gem_to_update, gems_in)
end


run_update
