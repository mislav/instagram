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
set :scss, Compass.sass_engine_options.merge(cache_location: File.join(ENV['TMPDIR'], 'sass-cache'))

set(:cache_dir) { File.join(ENV['TMPDIR'], 'cache') }

module Instagram::Cached
  def self.discover_user_id(url)
    url = Addressable::URI.parse url unless url.respond_to? :host
    $1.to_i if get_url(url) =~ %r{profiles/profile_(\d+)_}
  end
  
  setup settings.cache_dir, expires_in: 3.minutes
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
    text.sub(/\b(instagram)\b/i, '<a href="http://instagr.am">\1</a>')
  end
  
  def xhr?
    !(request.env['HTTP_X_REQUESTED_WITH'] !~ /XMLHttpRequest/i)
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
  
  expires 5.minutes, :public
  haml :index
end

get '/popular.atom' do
  @photos = Instagram::Cached::popular
  @title = "Instagram popular photos"
  
  content_type 'application/atom+xml', charset: 'utf-8'
  expires 15.minutes, :public
  last_modified @photos.first.taken_at if @photos.any?
  builder :feed, layout: false
end

get '/users/:id.atom' do
  @photos = user_photos params
  @title = "Photos by #{@photos.first.user.username} on Instagram" if @photos.any?
  
  content_type 'application/atom+xml', charset: 'utf-8'
  expires 15.minutes, :public
  last_modified @photos.first.taken_at if @photos.any?
  builder :feed, layout: false
end

get '/users/:id.json' do
  callback = params.delete('_callback')
  raw_json = user_photos(params, true)
  
  content_type "application/#{callback ? 'javascript' : 'json'}", charset: 'utf-8'
  expires 15.minutes, :public
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
    unless xhr?
      @user = Instagram::Cached::user_info params[:id]
      @title = "Photos by #{@user.username} on Instagram"
    end
  
    expires 5.minutes, :public
    last_modified @photos.first.taken_at if @photos.any?
    haml(xhr? ? :photos : :index)
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
  expires 1.hour, :public
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
  expires 6.hours, :public
  scss :style
end

__END__
@@ layout
!!!
%title&= @title
%meta{ 'http-equiv' => 'content-type', content: 'text/html; charset=utf-8' }
%link{ href: "/screen.css", rel: "stylesheet" }
- if @user
  %link{ href: "#{request.path}.atom", rel: 'alternate', title: "#{@user.username}'s photos", type: 'application/atom+xml' }
- elsif root_path?
  %link{ href: "/popular.atom", rel: 'alternate', title: @title, type: 'application/atom+xml' }
%script{ src: "/zepto.min.js" }

= yield

@@ index
%header
  %h1
    - if @user
      %img{ src: @user.avatar, class: 'avatar' }
    = instalink @title
    - if root_path?
      %a{ href: "/popular.atom", class: 'feed' }
        %img{ src: '/feed.png', alt: 'feed' }
  - if @user
    %p.stats
      &= @user.full_name
      &#8226;
      = @user.followers
      followers
      &#8226;
      %a{ href: "#{request.path}.atom", class: 'feed' }
        %span photo feed
        %img{ src: '/feed.png', alt: '' }

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
  $('#photos a.thumb').live('click', function(e) {
    e.preventDefault()
    $('#photos').addClass('lightbox')
    var item = $(this).closest('li').addClass('active')
    item.find('.full img').attr('src', $(this).attr('href'))
  })
  
  $('#photos a[href="#close"], #photos .full img').live('click', function(e) {
    e.preventDefault()
    $(this).closest('li').removeClass('active')
    $('#photos').removeClass('lightbox')
  })
  
  $('#photos .pagination a').live('click', function(e) {
    e.preventDefault()
    $(this).find('span').text('Loading...')
    var item = $(this).closest('.pagination')
    $.get($(this).attr('href'), function(body) {
      item.remove()
      try { $('#photos').append(body) }
      catch(e) { $('#photos').get(0).innerHTML += body } // for mozilla
    })
  })

@@ photos
- for photo in @photos
  %li
    %a{ href: photo.image_url(612), class: 'thumb' }
      - img(photo, 150)
    .full{ style: 'display:none' }
      %img{ width: 480, height: 480 }
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

@@ style
@import "compass/utilities";
@import "compass/css3/text-shadow";
@import "compass/css3/border-radius";

body {
  font: medium Helvetica, sans-serif;
  margin: 2em 4em;
}
h1, h2, h3 {
  font-family: "Myriad Pro Condensed", "Gill Sans", "Lucida Grande", Helvetica, sans-serif;
  font-weight: 100;
}
a:link, a:visited { color: darkblue }
a:hover, a:active { color: firebrick }

img { border: none }
h1 {
  color: #333;
  img.avatar { width: 30px; height: 30px }
  a:link, a:hover, a:active, a:visited { color: #555; font-weight: 400; text-decoration: none }
  a:hover { text-decoration: underline }
}
p.stats {
  margin-top: -1.1em;
  font-style: italic; font-size: 90%;
  color: gray;
  a.feed {
    text-decoration: none;
    &:link, &:visited { color: inherit; }
    span { text-decoration: underline }
    img { vertical-align: middle }
  }
}
article {
  h1 + nav { margin-top: -1.1em; font-size: 90%; }
  max-width: 40em;
  label { font-weight: bold }
  input[type=url] { font-size: 1.1em; width: 15em }
}

#photos {
  list-style: none;
  padding: 0; margin: 0;
  @include clearfix;
  li {
    display: inline;
    .thumb img { display: block; float: left; margin: 0 3px 3px 0 }
    &.active {
      .thumb { display: none }
      .full {
        display: block !important;
        padding: 15px;
        color: #F7F4E9;
        a { color: white }
        .close { margin-top: -1.15em; text-align: right; width: 480px }
      }
    }
    &.pagination {
      a {
        display: block; height: 20px; padding: 65px 0; width: 150px;
        text-align: center; float: left;
        font-size: 80%; text-decoration: none;
        span {
          padding: .2em .7em .3em;
          color: white; background: #bbb; 
          @include text-shadow(rgba(black, .4));
          @include border-radius(16px);
          white-space: nowrap;
        }
      }
      a:hover {
        background-color: #eee;
        span { background-color: #999; }
      }
    }
    h2 { font-size: 1.2em; margin: .5em 0; }
  }
  &.lightbox {
    background: #3F3831;
    li { display: none }
    li.active { display: block }
  }
}

footer {
  font-size: 80%;
  color: gray;
  max-width: 45em;
  margin: 2em auto;
  border-top: 1px solid silver;
  p { text-align: center; text-transform: uppercase; font-family: "Gill Sans", Helvetica, sans-serif; }
  a:link, a:hover, a:active, a:visited { color: #444 }
}