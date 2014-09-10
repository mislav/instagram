# encoding: utf-8
require 'sinatra'
require 'never_forget'
require_relative 'instagram'
require 'active_support/core_ext/object/blank'
require 'active_support/notifications'
require 'active_support/cache'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/time/acts_like'
# required for dalli:
require 'active_support/core_ext/string/encoding'
require 'active_support/cache'
require 'active_support/cache/dalli_store'
require 'digest/md5'
require 'haml'
require 'sass'
require 'compass'
require_relative 'models'
require 'yaml'
require 'choices'
require 'json'
require 'metriks/middleware'
require 'metriks/reporter/logger'

Choices.load_settings(File.join(settings.root, 'config.yml'), settings.environment.to_s).each do |key, value|
  set key.to_sym, value
end

Compass.configuration do |config|
  config.project_path = settings.root
  config.sass_dir = 'views'
end

set :haml, format: :html5
set :scss do
  Compass.sass_engine_options.merge style: settings.production? ? :compressed : :nested,
    cache_location: File.join(ENV['TMPDIR'], 'sass-cache')
end

set(:cache_dir) { File.join(ENV['TMPDIR'], 'cache') }

ENV['MEMCACHE_SERVERS']  = ENV['MEMCACHIER_SERVERS']
ENV['MEMCACHE_USERNAME'] = ENV['MEMCACHIER_USERNAME']
ENV['MEMCACHE_PASSWORD'] = ENV['MEMCACHIER_PASSWORD']

use Rack::Static, :urls => %w[
  /app.js
  /apple-touch-icon
  /favicon.ico
  /feed.png
  /spinner
  /zepto.min.js
], :root => 'public'

configure :production do
  require 'rack/cache'
  memcached = "memcached://%s:%s@%s" % [
    ENV['MEMCACHE_USERNAME'],
    ENV['MEMCACHE_PASSWORD'],
    ENV['MEMCACHE_SERVERS']
  ]
  use Rack::Cache, allow_reload: true,
    metastore:    "#{memcached}/meta",
    entitystore:  "#{memcached}/body?compress=true"
end

require 'rack/deflater'
use Rack::Deflater

Instagram.configure do |config|
  for key, value in settings.instagram
    config.send("#{key}=", value)
  end

  cache_options = { namespace: 'instagram', expires_in: settings.expires.api_cache }

  if settings.production?
    config.cache = ActiveSupport::Cache::DalliStore.new cache_options.merge(compress: true)
  else
    config.cache = ActiveSupport::Cache::FileStore.new settings.cache_dir, cache_options
  end
end

module Stats
  extend self

  def collection_name() 'stats' end
  def collection
    unless defined? @collection
      @collection = Mingo.connected? &&
        Mingo.db.create_collection(collection_name, capped: true, size: 1.megabyte)
    end
    @collection
  end

  def find(selector = {})
    collection.find(selector, :sort => ['$natural', -1])
  end

  def record(name)
    collection.update({hour: Time.now.strftime('%Y-%m-%d:%H')}, {'$inc' => {name => 1}}, upsert: true)
  end
end

configure :development, :production do
  begin
    Mingo.connect settings.mongodb.url
    User.collection.create_index(:username, :unique => true)
    User.collection.create_index(:user_id)
  rescue Mongo::ConnectionFailure
    warn "MongoDB connection failed: #{$!}"
  end

  ActiveSupport::Cache::Store.instrument = true

  strip_params = %w[access_token client_id client_secret]

  ActiveSupport::Notifications.subscribe('request.faraday') do |name, start, ending, _, payload|
    url = payload[:url]
    if url.query
      query_values = Faraday::Utils.parse_query url.query
      url = url.dup
      url.query = Faraday::Utils.build_query query_values.reject { |k,| strip_params.include? k }
    end
    $stderr.puts '[%s] %s %s (%.3f s)' % [url.host, payload[:method].to_s.upcase, url.request_uri, ending - start]

    Stats::record(:requests)
  end
  
  ActiveSupport::Notifications.subscribe(/^cache_(\w+).active_support$/) do |name, start, ending, _, payload|
    case name.split('.').first
    when 'cache_reuse_stale'
      $stderr.puts "Error rebuilding cache: %s (%s)" % [payload[:key], payload[:exception].message]
    when 'cache_generate'
      $stderr.puts "Cache rebuild: %s (%.3f s)" % [payload[:key], ending - start]
    when 'cache_read'
      # $stderr.puts "Cache hit: %s" % payload[:key] if payload[:hit]
    when 'cache_fetch_hit'
      # $stderr.puts "Cache hit: %s" % payload[:key]
    end
  end

  if settings.metriks_interval
    Metriks::Reporter::Logger.new(logger: Logger.new($stdout), interval: settings.metriks_interval).start
    use Metriks::Middleware
  end
end

helpers do
  def asset_host
    host = settings.asset_host
    host = "//#{host}" if host
    host
  end

  def instalink(text)
    text.sub(/\b(on instagram)\b/i, '<span>\1</span>').
      sub(/\b(instagram)\b/i, '<a href="http://instagr.am">\1</a>')
  end
  
  def photo_url(photo)
    absolute_url "/users/#{photo.user.username}#p#{photo.id}"
  end
  
  def user_url(user_id)
    absolute_url "/users/#{user_id}"
  end
  
  def atom_path(user)
    "/users/#{user.user_id}.atom"
  end
  
  def absolute_url(path)
    abs_uri = "#{request.scheme}://#{request.host}"

    if request.scheme == 'https' && request.port != 443 ||
          request.scheme == 'http' && request.port != 80
      abs_uri << ":#{request.port}"
    end

    abs_uri << path
  end
  
  def root_path?
    request.path == '/'
  end
  
  def user_path?
    request.path.index('/users/') == 0
  end
  
  def search_path?
    request.path.index('/search') == 0
  end
  
  def last_modified_from_photos(photos)
    if photos.any?
      last_modified Time.at(photos.first.created_time.to_i)
    end
  end

  def log_error(boom = $!, env = nil)
    super(boom, env) do |to_store|
      if to_store.exception.is_a? Instagram::Error
        params = (to_store['session'] ||= {})
        params.update('response_body' => to_store.exception.response.body)
      end
      yield to_store if block_given?
    end
  end

  def check_data(response)
    if 200 == response.status
      String === response ? response : response.data
    else
      response.error!
    end
  end

  def popular_photos
    check_data Instagram::media_popular
  end

  def user_photos(user, get_raw = false)
    check_data user.photos(params[:max_id], get_raw)
  end

  def lookup_user(id)
    User.lookup(id) do
      if id =~ /\D/
        not_found(
          haml "%h1 Unrecognized username\n%p We don't know user “#{params[:id]}”.\n" +
            "%p If this is your Instagram username, please go through the <a href='/help'>user discovery process</a>"
        )
      else
        not_found(
          haml "%h1 No such user\n%p Instagram couldn't resolve this user ID"
        )
      end
    end
  end

  def tag_search(query)
    check_data Instagram::tag_search(query)
  end

  def photos_by_tag(tag)
    check_data Instagram::tag_recent_media(tag, max_id: params[:max_id], count: 20)
  end
end

set :dump_errors, false
# set :show_exceptions, false

error User::NotAvailable do
  err = env['sinatra.error']
  msg = err.message

  if err.user.private_account?
    msg = "This user has a private account."
  elsif err.user.account_removed?
    msg = "This user is no longer active on Instagram."
  end

  case request.path
  when /\.json$/
    callback = params['_callback'] || params[:callback]
    content_type "application/#{callback ? 'javascript' : 'json'}", charset: 'utf-8'
    raw_json = JSON.dump error: msg

    status 400
    if callback
      "#{callback}(#{raw_json.strip})"
    else
      raw_json
    end
  when /\.atom$/
    content_type 'application/atom+xml', charset: 'utf-8'
    @photos = []
    @error_message = msg
    status 200
    builder :feed, layout: false
  else
    status 400
    haml "%h1 Error from Instagram\n%p #{msg}"
  end
end

error do
  err = env['sinatra.error']
  log_error err
  status 500

  Stats::record(:errors)

  if err.respond_to?(:response) and (body = err.response && err.response.body).is_a? Hash
    msg = if body['meta']
      "%s: %s" % [ body['meta']['error_type'], body['meta']['error_message'] ]
    else
      body['error_message'] || "Something is not right."
    end
    haml "%h1 Error from Instagram\n%p #{msg}"
  else
    haml "%h1 Error: can't perform this operation\n%p Please, try again later."
  end
end

configure :production do
  before do
    if request.get? && request.host != 'instagram.mislav.net'
      redirect "http://instagram.mislav.net#{request.fullpath}", 301
    end
  end
end

get '/' do
  @photos = popular_photos
  @title = "Instagram popular photos"
  
  expires settings.expires.popular_page, :public
  haml :index
end

get '/popular.atom' do
  @photos = popular_photos
  @title = "Instagram popular photos"
  
  content_type 'application/atom+xml', charset: 'utf-8'
  expires settings.expires.popular_feed, :public
  builder :feed, layout: false
end

get '/login' do
  return_url = request.url.split('?').first
  begin
    if params[:code]
      token_response = Instagram::get_access_token(return_to: return_url, code: params[:code])
      user = User.from_token token_response.body
      redirect user_url(user.username)
    elsif params[:error]
      status 401
      haml "%h1 Can't login: #{params[:error_description]}"
    else
      redirect Instagram::authorization_url(return_to: return_url).to_s
    end
  end
end

get '/users/:id.atom' do
  @user = User.find_by_user_id(params[:id]) or not_found
  @photos = user_photos(@user)
  @title = "Photos by #{@user.username} on Instagram"

  content_type 'application/atom+xml', charset: 'utf-8'
  expires settings.expires.user_feed, :public
  last_modified_from_photos(@photos)
  builder :feed, layout: false
end

get '/users/:id.json' do
  user = User.find_by_user_id(params[:id]) or not_found
  callback = params['_callback'] || params[:callback]
  raw_json = user_photos(user, :raw_json)
  
  content_type "application/#{callback ? 'javascript' : 'json'}", charset: 'utf-8'
  expires settings.expires.user_json, :public
  etag Digest::MD5.hexdigest(raw_json)
  
  if callback
    "#{callback}(#{raw_json.strip})"
  else
    raw_json
  end
end

get '/users/:id' do
  @user = lookup_user params[:id]
  # redirect from numeric ID to username
  redirect user_url(@user.username) unless params[:id] =~ /\D/

  @photos = user_photos(@user)
  @per_page = 20
  @title = "Photos by #{@user.username} on Instagram"

  expires settings.expires.user_page, :public
  last_modified_from_photos(@photos)
  haml(request.xhr? ? :photos : :index)
end

get '/search' do
  @query = params[:q]
  @title = "“#{@query}” tags on Instagram"
  @tags = tag_search(@query)
  @photos = []

  expires settings.expires.search_page, :public
  haml :index
end

get '/tags/:tag' do
  @tag = params[:tag]
  @title = "Photos tagged ##{@tag} on Instagram"
  @photos = photos_by_tag(@tag)
  @per_page = 20

  expires settings.expires.tag_page, :public
  haml(request.xhr? ? :photos : :index)
end

get '/help' do
  @title = "Help page"
  expires 1.month, :public
  haml :help
end

post '/users/discover' do
  begin
    url = params[:url].presence
    twitter = params[:twitter].presence
    twitter_id = nil
    
    if twitter and not url
      url, twitter_id = Instagram::Discovery.search_twitter(params[:twitter])
    end
    
    user = url && User.find_by_instagram_url(url)
    
    if user
      if twitter_id
        user.twitter = twitter
        user.twitter_id = twitter_id
        user.save
      end
      redirect user_url(user.username)
    else
      status 404
      haml "%h1 Sorry\n%p The user ID couldn't be discovered on this page.\n" +
        "%p <strong>Note:</strong> you <em>must</em> have a profile picture on Instagram."
    end
  rescue
    log_error
    raise unless settings.production?
    status 500
    haml "%h1 Error\n%p The user ID couldn't be discovered because of an error"
  end
end

get '/screen.css' do
  expires 1.month, :public
  scss :style
end

get '/_stats' do
  stats = Stats.find.limit(24)
  content_type 'text/plain'
  stats.map { |i|
    "[%s] requests: %d, errors: %d" % [ i['hour'], i['requests'].to_i, i['errors'].to_i ]
  }.join("\n")
end

get '/google2a2c9e15ef02ca5d.html' do
  "google-site-verification: google2a2c9e15ef02ca5d.html"
end

__END__
@@ layout
!!!
%title&= @title
%meta{ 'http-equiv' => 'content-type', content: 'text/html; charset=utf-8' }
%meta{ name: 'viewport', content: 'initial-scale=1.0, maximum-scale=1.0, user-scalable=no' }
%link{ rel: 'apple-touch-icon', href: "#{asset_host}/apple-touch-icon.png" }
%link{ rel: 'favicon', href: "#{asset_host}/favicon.ico" }
/ %meta{ name: 'apple-mobile-web-app-capable', content: 'yes' }
/ %meta{ name: 'apple-mobile-web-app-status-bar-style', content: 'black' }
%link{ href: "#{asset_host}/screen.css", rel: "stylesheet" }
- if @user
  %link{ href: atom_path(@user), rel: 'alternate', title: "#{@user.username}'s photos", type: 'application/atom+xml' }
- elsif root_path?
  %link{ href: "/popular.atom", rel: 'alternate', title: @title, type: 'application/atom+xml' }

= yield

- if settings.production?
  :javascript
    var _gauges = _gauges || [];
    (function() {
      var t = document.createElement('script'); t.type = 'text/javascript'; t.async = true;
      t.id = 'gauges-tracker'; t.src = '//secure.gaug.es/track.js';
      t.setAttribute('data-site-id', '4e417aeff5a1f5142f000001');
      var s = document.getElementsByTagName('script')[0];
      s.parentNode.insertBefore(t, s);
    })();

@@ index
%header
  %h1
    - if @user
      %img{ src: @user.profile_picture, class: 'avatar' }
    = instalink @title
    - if root_path?
      %a{ href: "/popular.atom", class: 'feed' }
        %img{ src: '/feed.png', alt: 'feed', width: 14, height: 14 }

  - if root_path? or search_path?
    %form{ action: '/search', method: 'get' }
      %p
        %input{ type: 'search', name: 'q', placeholder: 'search tags', value: @query }
        %input{ type: 'submit', value: 'Search' }
  - elsif @user
    %p.stats
      &= @user.full_name
      &#8226;
      = @user.counts.followed_by
      followers
      &#8226;
      %a{ href: atom_path(@user), class: 'feed' }
        %span photo feed
        %img{ src: '/feed.png', alt: '', width: 14, height: 14 }

  - if @tags and @tags.any?
    %ol.tags
      - for tag in @tags.sort_by(&:media_count).reverse[0, 6]
        %li
          %a{ href: "/tags/#{tag.name}" }== ##{tag.name}
          %span== (#{tag.media_count})

%ol#photos
  = haml :photos

%footer
  %p
    - unless root_path?
      &larr; <a href="/">Home</a> &#8226;
    <a href="/help">Help</a> &#8226;
    App made by <a href="http://twitter.com/mislav">@mislav</a>
    (<a href="/users/mislav" title="Mislav's photos">photos</a>)

:javascript
  document.write('<script src=' +
  ('__proto__' in {} ? '#{asset_host}/zepto' :
   'https://ajax.googleapis.com/ajax/libs/jquery/1.4.4/jquery') +
  '.min.js><\/script>')

%script{ src: "#{asset_host}/app.js" }

@@ photos
- for photo in @photos
  %li{ id: "media_#{photo.id}" }
    %a{ href: photo.images.standard_resolution.url, class: 'thumb' }
      %img{ src: photo.images.thumbnail.url, width: 150, height: 150 }
    .full{ style: 'display:none' }
      %img{ width: 480, height: 480 }
      .caption
        - if photo.caption
          %h2= photo.caption.text
        .author
          by
          - user_name = photo.user.full_name.presence || photo.user.username
          - if photo.user.id
            %a{ href: "/users/#{photo.user.id}" }&= user_name
          - else
            &= user_name
        .close
          %a{ href: "#close" } close

- if @photos.respond_to?(:next_page) ? @photos.next_page : (@photos.length >= (@per_page || 20) and not root_path?)
  %li.pagination
    %a{ href: request.path + "?max_id=#{@photos.last.id}" } <span>Load more &rarr;</span>

@@ feed
schema_date = 2010
popular = request.path.include? 'popular'

xml.feed "xml:lang" => "en-US", xmlns: 'http://www.w3.org/2005/Atom' do
  xml.id "tag:#{request.host},#{schema_date}:#{request.path.split(".")[0]}"
  xml.link rel: 'alternate', type: 'text/html', href: request.url.split(popular ? 'popular' : '.')[0]
  xml.link rel: 'self', type: 'application/atom+xml', href: request.url
  
  xml.title @title

  if defined? @error_message
    xml.entry do
      xml.title "Error"
      xml.id "tag:#{request.host},#{schema_date}:Error"

      xml.content @error_message, type: 'text'
    end
  end
  
  if @photos.any?
    xml.updated Time.at(@photos.first.created_time.to_i).xmlschema
    xml.author { xml.name @photos.first.user.full_name } unless popular
  end
  
  for photo in @photos
    xml.entry do 
      xml.title((photo.caption && photo.caption.text) || 'Photo')
      xml.id "tag:#{request.host},#{schema_date}:Instagram::Media/#{photo.id}"
      published_at = Time.at(photo.created_time.to_i).xmlschema
      xml.published published_at
      xml.updated   published_at
      
      if popular
        xml.link rel: 'alternate', type: 'text/html', href: user_url(photo.user.id)
        xml.author { xml.name photo.user.full_name }
      else
        xml.link rel: 'alternate', type: 'text/html', href: photo_url(photo)
      end
      
      xml.content type: 'xhtml' do |content|
        content.div xmlns: "http://www.w3.org/1999/xhtml" do
          content.img src: photo.images.low_resolution.url, width: 306, height: 306, alt: photo.caption && photo.caption.text
          content.p "#{photo.likes.count} likes" if popular
        end
      end
    end
  end
end
