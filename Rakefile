task :app do
  $LOAD_PATH.unshift File.expand_path('..', __FILE__)
  require 'app'
end

task :clear => :app do
  require 'fileutils'
  FileUtils.rm_r Instagram.cache.cache_path, :verbose => true
end
