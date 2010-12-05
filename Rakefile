task :app do
  $LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
  $LOAD_PATH.unshift File.dirname($LOAD_PATH.first)
  require 'app'
end

task :clear => :app do
  items = CachedInstagram.cache.clear
  puts "#{items.size} removed"
end