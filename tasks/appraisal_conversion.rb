require 'pathname'

# This module translates our custom mapping between appraisal and bundler.
#
# It cannot be included into `Appraisal` file, because it was invoked via `instance_eval`.
module AppraisalConversion
  module_function

  @gemfile_dir = 'gemfiles'
  @definition_dir = 'appraisal'

  def to_bundle_gemfile(group)
    gemfile = "#{runtime_identifier}_#{group}.gemfile".tr('-', '_')
    path = root_path.join(gemfile_dir, gemfile)

    if path.exist?
      path.to_s
    else
      raise "Gemfile not found at #{path}"
    end
  end

  def definition
    path = root_path.join(@definition_dir, "#{runtime_identifier}.rb")

    if path.exist?
      path.to_s
    else
      raise "Definition not found at #{path}"
    end
  end

  def runtime_identifier
    major, minor, = Gem::Version.new(RUBY_ENGINE_VERSION).segments
    "#{RUBY_ENGINE}-#{major}.#{minor}"
  end

  def gemfile_pattern
    root_path + gemfile_dir + "#{runtime_identifier.tr('-', '_')}_*.gemfile"
  end

  def gemfile_dir
    @gemfile_dir
  end

  def root_path
    Pathname.pwd
  end
end
