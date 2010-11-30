$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift File.expand_path('..', __FILE__)
require 'app'

run Sinatra::Application