require 'rubygems'
require 'bundler'

Bundler.setup
app_root = ENV['APP_ROOT'] || File.expand_path('..', __FILE__)

Encoding.default_external = 'utf-8'

require File.join(app_root, 'app')
run Sinatra::Application
