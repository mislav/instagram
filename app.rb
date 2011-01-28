# encoding: utf-8
require 'sinatra'
require 'instagram/cached'
require 'active_support/notifications'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/time/acts_like'
require 'digest/md5'
require 'haml'
require 'sass'
require 'compass'

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

module Instagram::Cached
  def self.discover_user_id(url)
    url = Addressable::URI.parse url unless url.respond_to? :host
    $1.to_i if get_url(url) =~ %r{profiles/profile_(\d+)_}
  end
  
  setup settings.cache_dir, expires_in: settings.production? ? 3.minutes : 1.hour
end

configure :development, :production do
  ActiveSupport::Cache::Store.instrument = true

  ActiveSupport::Notifications.subscribe(/^cache_(\w+).active_support$/) do |name, start, ending, _, payload|
    case name.split('.').first
    when 'cache_reuse_stale'
      $stderr.puts "Error rebuilding cache: %s (%s)" % [payload[:key], payload[:exception].message]
    when 'cache_generate'
      $stderr.puts "Cache rebuild: %s (%.3f s)" % [payload[:key], ending - start]
    end
  end
end

configure :development do
  set :logging, false
end

helpers do
  def img(photo, size)
    haml_tag :img, src: photo.image_url(size), width: size, height: size
  end
  
  def instalink(text)
    text.sub(/\b(on instagram)\b/i, '<span>\1</span>').
      sub(/\b(instagram)\b/i, '<a href="http://instagr.am">\1</a>')
  end
  
  def user_photos(params, raw = false)
    feed_params = params[:max_id] ? { max_id: params[:max_id].to_s } : {}
    options = raw ? { parse_with: nil } : {}
    Instagram::Cached::by_user(params[:id], feed_params, options)
  end
  
  def user_url(user)
    absolute_url "/users/#{user.id}"
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
end

get '/' do
  @photos = Instagram::Cached::popular
  @title = "Instagram popular photos"
  
  expires 15.minutes, :public
  haml :index
end

get '/popular.atom' do
  @photos = Instagram::Cached::popular
  @title = "Instagram popular photos"
  
  content_type 'application/atom+xml', charset: 'utf-8'
  expires 1.hour, :public
  last_modified @photos.first.taken_at if @photos.any?
  builder :feed, layout: false
end

get '/users/:id.atom' do
  @photos = user_photos params
  @title = "Photos by #{@photos.first.user.username} on Instagram" if @photos.any?
  
  content_type 'application/atom+xml', charset: 'utf-8'
  expires 1.hour, :public
  last_modified @photos.first.taken_at if @photos.any?
  builder :feed, layout: false
end

get '/users/:id.json' do
  callback = params.delete('_callback')
  raw_json = user_photos(params, true)
  
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
    @photos = user_photos params
    unless request.xhr?
      @user = Instagram::Cached::user_info params[:id]
      @title = "Photos by #{@user.username} on Instagram"
    end
  
    expires 30.minutes, :public
    last_modified @photos.first.taken_at if @photos.any?
    haml(request.xhr? ? :photos : :index)
  rescue Net::HTTPServerException => e
    if 404 == e.response.code.to_i
      status 404
      haml "%h1 No such user\n%p Instagram couldn't resolve this user ID"
    else
      status 500
      haml "%h1 Error fetching user\n%p The user ID couldn't be discovered because of an error"
    end
  end
end

get '/help' do
  @title = "Help page"
  expires 1.month, :public
  haml :help
end

post '/users/discover' do
  begin
    user_id = Instagram::Cached::discover_user_id(params[:url])
  
    if user_id
      redirect "/users/#{user_id}"
    else
      status 500
      haml "%h1 Sorry\n%p The user ID couldn't be discovered on this page"
    end
  rescue
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
  %link{ href: "#{request.path}.atom", rel: 'alternate', title: "#{@user.username}'s photos", type: 'application/atom+xml' }
- elsif root_path?
  %link{ href: "/popular.atom", rel: 'alternate', title: @title, type: 'application/atom+xml' }

= yield

- if settings.production?
  :javascript
    var _gaq = _gaq || [];
    _gaq.push(['_setAccount', 'UA-87067-8']);
    _gaq.push(['_trackPageview']);

    (function() {
      var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
      ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
      var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
    })();

@@ index
%header
  %h1
    - if @user
      %img{ src: @user.avatar, class: 'avatar' }
    = instalink @title
    - if root_path?
      %a{ href: "/popular.atom", class: 'feed' }
        %img{ src: '/feed.png', alt: 'feed', width: 14, height: 14 }
  - if @user
    %p.stats
      &= @user.full_name
      &#8226;
      = @user.followers
      followers
      &#8226;
      %a{ href: "#{request.path}.atom", class: 'feed' }
        %span photo feed
        %img{ src: '/feed.png', alt: '', width: 14, height: 14 }

%ol#photos
  = haml :photos

%footer
  %p
    - if @user
      &larr; <a href="/">Home</a> &#8226;
    <a href="/help">Help</a> &#8226;
    App made by <a href="http://twitter.com/mislav">@mislav</a>
    (<a href="/users/35241" title="Mislav's photos">photos</a>)
    using <a href="https://github.com/mislav/instagram">Instagram Ruby client</a>

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
    %a{ href: photo.image_url(612), class: 'thumb' }
      - img(photo, 150)
    .full{ style: 'display:none' }
      %img{ width: 480, height: 480 }
      .caption
        %h2= photo.caption
        .author
          by
          %a{ href: "/users/#{photo.user.id}" }&= photo.user.full_name
        .close
          %a{ href: "#close" } close
- if @photos.length >= 20 and not root_path?
  %li.pagination
    %a{ href: request.path + "?max_id=#{@photos.last.id}" } <span>Load more &rarr;</span>

@@ help
%article
  %h1= @title
  %nav
    &larr; <a href="/">Home</a>
  
  %section
    %h2 What's this site?

    %p This site is the unofficial Instagram front-end on the Web made by querying the <strong>public resources</strong> of the <a href="https://github.com/mislav/instagram/wiki">Instagram API</a>.

  %section
    %h2 How do I discover my own Instagram photos?

    %p Unfortunately, it isn't straightforward. To fetch your photos this site has to know your user ID, and Instagram doesn't have a method to lookup your ID from your username. Their API has search functionality, but it requires authentication.

    %p There is a way, however. If you have a permalink to one of your photos (for instance, if you setup Instagram to tweet your photo) paste the URL here and your user ID can be detected:

    %form{ action: '/users/discover', method: 'post' }
      %p
        %label
          Instagr.am permalink:
          %input{ type: 'url', name: 'url', placeholder: 'http://instagr.am/p/..../' }
          %input{ type: 'submit', value: 'Miracle!' }

  %section
    %h2 What about geolocated photos?
  
    %p Some photos have location information, but it isn't visible right now. I might add this functionality.
  
  %section
    %h2 Why doesn't Instagram have a real website?
    
    %p They mentioned that their public site is coming out soon.

@@ feed
schema_date = 2010
popular = request.path.include? 'popular'

xml.feed "xml:lang" => "en-US", xmlns: 'http://www.w3.org/2005/Atom' do
  xml.id "tag:#{request.host},#{schema_date}:#{request.path.split(".")[0]}"
  xml.link rel: 'alternate', type: 'text/html', href: request.url.split(popular ? 'popular' : '.')[0]
  xml.link rel: 'self', type: 'application/atom+xml', href: request.url
  
  xml.title @title
  
  if @photos.any?
    xml.updated @photos.first.taken_at.xmlschema
    xml.author { xml.name @photos.first.user.full_name } unless popular
  end
  
  for photo in @photos
    xml.entry do 
      xml.title photo.caption || 'Photo'
      xml.id "tag:#{request.host},#{schema_date}:Instagram::Media/#{photo.id}"
      xml.published photo.taken_at.xmlschema
      
      if popular
        xml.link rel: 'alternate', type: 'text/html', href: user_url(photo.user)
        xml.author { xml.name photo.user.full_name }
      end
      
      xml.content type: 'xhtml' do |content|
        content.div xmlns: "http://www.w3.org/1999/xhtml" do
          content.img src: photo.image_url(306), width: 306, height: 306, alt: photo.caption
          content.p "#{photo.likers.size} likes" if popular and not photo.likers.empty?
        end
      end
    end
  end
end
