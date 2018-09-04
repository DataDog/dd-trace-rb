def ruby_version(version, java_required = false, &block)
  return if java_required && RUBY_PLATFORM != 'java'

  version = Gem::Version.new(version)
  current_version = Gem::Version.new(RUBY_VERSION)

  yield if current_version >= version && current_version < version.bump
end

def do_appraise(name, *closures, &block)
  @common_appraisals ||= {}
  @versions ||= {}
  @versions[name] ||= {}
  versions = @versions[name].dup
  common_appraisal = @common_appraisals[name]

  appraise(name) do
    closures.each do |closure|
      instance_exec(versions, &closure)
    end

    instance_exec(versions, &common_appraisal) if common_appraisal
    instance_exec(versions, &block) if block_given?
  end
end

def common_appraisal(name, &block)
  @common_appraisals ||= {}
  @common_appraisals[name] = block
end

def version(versions = {})
  proc do |appraisal_version|
    appraisal_version.merge!(versions)
  end
end
