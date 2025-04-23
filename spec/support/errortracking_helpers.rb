require 'datadog/core/errortracking/component'
require 'support/platform_helpers'

module ErrortrackingHelpers
  def self.generate_test_env
    require 'tmpdir'
    require 'fileutils'

    # Create a mock gem structure
    gem_root = Dir.mktmpdir('mock_gem')
    gem_lib_dir = File.join(gem_root, 'gems/mock-gem-2.1.1/lib')
    FileUtils.mkdir_p(gem_lib_dir)

    # Create mock gem files
    create_gem(gem_lib_dir)

    # Add gem path to load path
    $LOAD_PATH.unshift(gem_lib_dir)
    [gem_root, gem_lib_dir]
  end

  def self.create_gem(gem_lib_dir)
    # Create a typical gem structure with nested directories
    FileUtils.mkdir_p(File.join(gem_lib_dir, 'mock_gem'))

    create_main_gem_file(gem_lib_dir)
    create_client_file(gem_lib_dir)
    create_utils_file(gem_lib_dir)
  end

  def self.create_main_gem_file(gem_lib_dir)
    File.open(File.join(gem_lib_dir, 'mock_gem.rb'), 'w') do |f|
      f.write <<-RUBY
        require 'mock_gem/client'
        require 'mock_gem/utils'
        module MockGem
          VERSION = '2.1.1'
        end
      RUBY
    end
  end

  def self.create_client_file(gem_lib_dir)
    File.open(File.join(gem_lib_dir, 'mock_gem/client.rb'), 'w') do |f|
      f.write <<-RUBY
        module MockGem
          class Client
            def self.rescue_error
              begin
                raise 'mock_gem client error'
              rescue => e
                return e
              end
            end
          end
        end
      RUBY
    end
  end

  def self.create_utils_file(gem_lib_dir)
    File.open(File.join(gem_lib_dir, 'mock_gem/utils.rb'), 'w') do |f|
      f.write <<-RUBY
        module MockGem
          module Utils
            def self.rescue_error
              begin
                raise 'mock_gem utils error'
              rescue => e
                return e
              end
            end
          end
        end
      RUBY
    end
  end
end
