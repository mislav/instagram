# encoding: utf-8
require 'sinatra'
require 'never_forget'
require 'instagram'
require 'active_support/core_ext/object/blank'
require 'active_support/notifications'
require 'active_support/cache'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/time/acts_like'
require 'addressable/uri'
require 'digest/md5'
require 'haml'
require 'sass'
require 'compass'
require 'models'
require 'choices'

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

set(:search_index) {
  search_client = IndexTank::Client.new(settings.indextank.api_url)
  search_client.indexes('idx')
}

set(:cache_dir) { File.join(ENV['TMPDIR'], 'cache') }

Instagram.configure do |config|
  for key, value in settings.instagram
    config.send("#{key}=", value)
  end

  config.cache = ActiveSupport::Cache::FileStore.new settings.cache_dir,
    namespace: 'instagram',
    expires_in: settings.production? ? 3.minutes : 1.hour
end

configure :development, :production do
  begin
    Mingo.connect settings.mongodb.url
    User.collection.create_index(:username, :unique => true)
  rescue Mongo::ConnectionFailure
    warn "MongoDB connection failed: #{$!}"
  end

  ActiveSupport::Cache::Store.instrument = true

  ActiveSupport::Notifications.subscribe('search.indextank') do |name, start, ending, _, payload|
    $stderr.puts 'IndexTank search for "%s" (%.3f s)' % [payload[:query], ending - start]
  end

  strip_params = %w[access_token client_id client_secret]

  ActiveSupport::Notifications.subscribe('request.faraday') do |name, start, ending, _, payload|
    url = payload[:url]
    if url.query_values and (url.query_values.keys & strip_params).any?
      url = url.dup
      url.query_values = url.query_values.reject { |k,| strip_params.include? k }
    end
    $stderr.puts '[%s] %s %s (%.3f s)' % [url.host, payload[:method].to_s.upcase, url.request_uri, ending - start]
  end
  
  ActiveSupport::Notifications.subscribe(/^cache_(\w+).active_support$/) do |name, start, ending, _, payload|
    case name.split('.').first
    when 'cache_reuse_stale'
      $stderr.puts "Error rebuilding cache: %s (%s)" % [payload[:key], payload[:exception].message]
    when 'cache_generate'
      $stderr.puts "Cache rebuild: %s (%.3f s)" % [payload[:key], ending - start]
    when 'cache_read'
      $stderr.puts "Cache hit: %s" % payload[:key] if payload[:hit]
    end
  end
end

configure :development do
  set :logging, false
end

FILTERS = {
  1 => 'X-Pro II',
  2 => 'Lomo-fi',
  3 => 'Earlybird',
  4 => 'Apollo',
  5 => 'Poprocket',
  10 => 'Inkwell',
  13 => 'Gotham',
  14 => '1977',
  15 => 'Nashville',
  16 => 'Lord Kelvin',
  17 => 'Lily',
  18 => 'Sutro',
  19 => 'Toaster',
  20 => 'Walden',
  21 => 'Hefe'
}

helpers do
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
  
  def search_page(page)
    Addressable::URI.parse(request.path).tap do |url|
      url.query_values = params.merge('page' => page.to_s)
    end
  end
  
  def last_modified_from_photos(photos)
    if photos.any?
      last_modified Time.at(photos.first.created_time.to_i)
    end
  end
end

error do
  log_error env['sinatra.error']
  status 500
  haml "%h1 Error: can't perform this operation\n%p Please, try again later."
end

get '/' do
  @photos = Instagram::media_popular
  @title = "Instagram popular photos"
  
  expires 15.minutes, :public
  haml :index
end

get '/popular.atom' do
  @photos = Instagram::media_popular
  @title = "Instagram popular photos"
  
  content_type 'application/atom+xml', charset: 'utf-8'
  expires 1.hour, :public
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
  rescue Faraday::Error::ClientError => error
    log_error error
    status 500
    haml "%h1 Instagram error: #{error.response[:body]['error_message']}"
  end
end

get '/users/:id.atom' do
  @user = User.find_by_user_id(params[:id]) or not_found
  @photos = @user.photos params[:max_id]
  @title = "Photos by #{@user.username} on Instagram"
  
  content_type 'application/atom+xml', charset: 'utf-8'
  expires 1.hour, :public
  last_modified_from_photos(@photos)
  builder :feed, layout: false
end

get '/users/:id.json' do
  user = User.find_by_user_id(params[:id]) or not_found
  callback = params['_callback']
  raw_json = user.photos(params[:max_id], :raw_json)
  
  content_type "application/#{callback ? 'javascript' : 'json'}", charset: 'utf-8'
  expires 1.hour, :public
  etag Digest::MD5.hexdigest(raw_json)
  
  if callback
    "#{callback}(#{raw_json.strip})"
  else
    raw_json
  end
end

get '/users/:id' do
  begin
    @user = User.lookup params[:id]
    # redirect from numeric ID to username
    redirect user_url(@user.username) unless params[:id] =~ /\D/
    @photos = @user.photos params[:max_id]
    @per_page = 20
  rescue Faraday::Error::ClientError => e
    log_error e
    message = e.response[:body]['meta']['error_message']

    if "this user does not exist" == message
      User.delete params[:id]
      status 404
      haml "%h1 No such user\n%p Instagram couldn't resolve this user ID"
    else
      status 500
      haml "%h1 Error fetching data from Instagram\n%p The error was: #{message}"
    end
  rescue User::NotFound
    status 404
    haml "%h1 Unrecognized username\n%p We don't know user “#{params[:id]}”.\n" +
      "%p If this is your Instagram username, please go through the <a href='/help'>user discovery process</a>"
  else
    @title = "Photos by #{@user.username} on Instagram"

    expires 30.minutes, :public
    last_modified_from_photos(@photos)
    haml(request.xhr? ? :photos : :index)
  end
end

get '/search' do
  @query = params[:q]
  @title = "“#{@query}” on Instagram"
  @tags = Instagram::tag_search(@query)

  @filter_name = FILTERS[params[:filter].to_i]
  @photos = IndexedPhoto.paginate(@query, :page => params[:page], :filter => @filter_name)

  expires 10.minutes, :public
  haml(request.xhr? ? :photos : :index)
end

get '/tags/:tag' do
  @tag = params[:tag]
  @title = "Photos tagged ##{@tag} on Instagram"
  @photos = Instagram::tag_recent_media(@tag, max_id: params[:max_id], count: 20)
  @per_page = 20

  expires 10.minutes, :public
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
      status 500
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

__END__
@@ layout
!!!
%title&= @title
%meta{ 'http-equiv' => 'content-type', content: 'text/html; charset=utf-8' }
%meta{ name: 'viewport', content: 'initial-scale=1.0; maximum-scale=1.0; user-scalable=0;' }
%link{ rel: 'apple-touch-icon', href: '/apple-touch-icon.png' }
%link{ rel: 'favicon', href: '/favicon.ico' }
/ %meta{ name: 'apple-mobile-web-app-capable', content: 'yes' }
/ %meta{ name: 'apple-mobile-web-app-status-bar-style', content: 'black' }
%link{ href: "/screen.css", rel: "stylesheet" }
- if @user
  %link{ href: atom_path(@user), rel: 'alternate', title: "#{@user.username}'s photos", type: 'application/atom+xml' }
- elsif root_path?
  %link{ href: "/popular.atom", rel: 'alternate', title: @title, type: 'application/atom+xml' }

= yield

- if settings.production?
  :javascript
    var _gaq = _gaq || [];
    var _gauges = _gauges || [];
    _gaq.push(['_setAccount', 'UA-87067-8']);
    _gaq.push(['_setDetectFlash', false]);
    _gaq.push(['_trackPageview']);

    (function() {
      var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
      ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
      var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);

      var t = document.createElement('script'); t.type = 'text/javascript'; t.async = true;
      t.id = 'gauges-tracker'; t.src = '//secure.gaug.es/track.js';
      t.setAttribute('data-site-id', '4e417aeff5a1f5142f000001');
      s = document.getElementsByTagName('script')[0];
      s.parentNode.insertBefore(t, s);
    })();

@@ index
%header
  %h1
    - if @user
      %img{ src: @user.instagram_info.profile_picture, class: 'avatar' }
    = instalink @title
    - if root_path?
      %a{ href: "/popular.atom", class: 'feed' }
        %img{ src: '/feed.png', alt: 'feed', width: 14, height: 14 }

  - if root_path? or search_path?
    %form{ action: '/search', method: 'get' }
      %p
        %input{ type: 'search', name: 'q', placeholder: 'search photos', value: @query }
        %select{ name: 'filter' }
          %option{ value: '' } any filter
          - FILTERS.each do |code, name|
            %option{ value: code, selected: @filter_name == name }&= name
        %input{ type: 'submit', value: 'Search' }
  - elsif @user
    %p.stats
      &= @user.instagram_info.full_name
      &#8226;
      = @user.instagram_info.counts.followed_by
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

  - if search_path?
    %p.stats
      == Found <b>#{@photos.total_entries}</b> items
      - if @filter_name
        == using the “#{@filter_name}” filter

%ol#photos
  = haml :photos

- if search_path?
  %p.footnote
    <strong>Note:</strong> search is limited &mdash; not all photos appear in the results.

%footer
  %p
    - unless root_path?
      &larr; <a href="/">Home</a> &#8226;
    <a href="/help">Help</a> &#8226;
    App made by <a href="http://twitter.com/mislav">@mislav</a>
    (<a href="/users/mislav" title="Mislav's photos">photos</a>)

:javascript
  var src, script
  if (navigator.userAgent.match(/WebKit\b/)) src = '/zepto.min.js'
  else src = 'https://ajax.googleapis.com/ajax/libs/jquery/1.4.4/jquery.min.js'
  script = document.createElement('script')
  script.src = src
  script.async = 'async'
  document.body.appendChild(script)

%script{ src: '/app.js' }

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
  - href = search_path? ? search_page(@photos.next_page) : request.path + "?max_id=#{@photos.last.id}"
  %li.pagination
    %a{ href: href } <span>Load more &rarr;</span>

@@ feed
schema_date = 2010
popular = request.path.include? 'popular'

xml.feed "xml:lang" => "en-US", xmlns: 'http://www.w3.org/2005/Atom' do
  xml.id "tag:#{request.host},#{schema_date}:#{request.path.split(".")[0]}"
  xml.link rel: 'alternate', type: 'text/html', href: request.url.split(popular ? 'popular' : '.')[0]
  xml.link rel: 'self', type: 'application/atom+xml', href: request.url
  
  xml.title @title
  
  if @photos.any?
    xml.updated Time.at(@photos.first.created_time.to_i).xmlschema
    xml.author { xml.name @photos.first.user.full_name } unless popular
  end
  
  for photo in @photos
    xml.entry do 
      xml.title((photo.caption && photo.caption.text) || 'Photo')
      xml.id "tag:#{request.host},#{schema_date}:Instagram::Media/#{photo.id}"
      xml.published Time.at(photo.created_time.to_i).xmlschema
      
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
