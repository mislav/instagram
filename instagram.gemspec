# encoding: utf-8

Gem::Specification.new do |gem|
  gem.name    = 'instagram'
  gem.version = '0.3.2'
  gem.date    = Time.now.strftime('%Y-%m-%d')

  gem.add_dependency 'addressable'
  gem.add_dependency 'yajl-ruby'
  gem.add_dependency 'nibbler', '>= 1.2.0'

  gem.summary = "Instagram API client"
  gem.description = "Ruby library for consuming the Instagram public API."

  gem.authors  = ['Mislav Marohnić']
  gem.email    = 'mislav.marohnic@gmail.com'
  gem.homepage = 'http://github.com/mislav/instagram'

  gem.rubyforge_project = nil
  gem.has_rdoc = false
  # gem.rdoc_options = ['--main', 'README.rdoc', '--charset=UTF-8']
  # gem.extra_rdoc_files = ['README.rdoc', 'LICENSE', 'CHANGELOG.rdoc']

  gem.files = Dir['Rakefile', '{bin,lib,man,test,spec}/**/*', 'README*', '*LICENSE*']
end
