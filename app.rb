# encoding: utf-8
require 'sinatra'
require 'active_support/cache'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/time/acts_like'
require 'instagram'
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

module CachedInstagram
  extend Instagram
  @cache = ActiveSupport::Cache::FileStore.new(settings.cache_dir, expire_in: 5.minutes)
  
  class << self
    private
    def get_url(url)
      @cache.fetch("instagram/#{url}") { super }
    end
  end
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
  
  def user_photos(params)
    feed_params = params[:max_id] ? { max_id: params[:max_id].to_s } : {}
    CachedInstagram::by_user(params[:id], feed_params)
  end
end

get '/' do
  @photos = CachedInstagram::popular
  @title = "Instagram popular items"
  
  expires 30.minutes, :public
  haml :index
end

get '/users/:id.atom' do
  @photos = user_photos params
  @title = "Photos by #{@photos.first.user.username} on Instagram" if @photos.any?
  
  content_type 'application/atom+xml', charset: 'utf-8'
  expires 1.hour, :public
  builder :feed, :layout => false
end

get '/users/:id' do
  @photos = user_photos params
  unless xhr?
    @user = CachedInstagram::user_info params[:id]
    @title = "Photos by #{@user.username} on Instagram"
  end
  
  expires 30.minutes, :public
  haml(xhr? ? :photos : :index)
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
%script{ src: "/zepto.min.js" }

= yield

@@ index
%header
  %h1
    - if @user
      %img{ src: @user.avatar, class: 'avatar' }
    = instalink @title
  - if @user
    %p.stats
      &= @user.full_name
      &#8226;
      = @user.followers
      followers

%ol#photos
  = haml :photos

%footer
  %p
    - if @user
      &larr; <a href="/">Home</a> &#8226;
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
- if @user and @photos.length >= 20
  %li.pagination
    %a{ href: request.path + "?max_id=#{@photos.last.id}" } <span>Load more &rarr;</span>

@@ feed
schema_date = 2010

xml.feed "xml:lang" => "en-US", "xmlns" => 'http://www.w3.org/2005/Atom' do
  xml.id("tag:#{request.host},#{schema_date}:#{request.path.split(".")[0]}")
  xml.link(:rel => 'alternate', :type => 'text/html', :href => request.url.split(".")[0])
  xml.link(:rel => 'self', :type => 'application/atom+xml', :href => request.url)
  
  xml.title @title
  xml.updated @photos.first.taken_at if @photos.any?
  
  for photo in @photos
    xml.entry do 
      xml.title photo.caption || 'Photo'
      xml.id("tag:#{request.host},#{schema_date}:Instagram::Media/#{photo.id}")
      xml.published photo.taken_at
      # xml.link(:rel => 'alternate', :type => 'text/html', :href => options[:url])
      xml.content :type => 'xhtml' do |content|
        content.img :src => photo.image_url(306), :width => 306, :height => 306, :alt => photo.caption
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

img { border: none }
h1 {
  color: #333;
  img.avatar { width: 30px; height: 30px }
  a { color: #555; font-weight: 400; text-decoration: none }
  a:hover { text-decoration: underline }
}
p.stats { color: gray; font-style: italic; font-size: 90%; margin-top: -1.1em }

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
  max-width: 40em;
  margin: 2em auto;
  border-top: 1px solid silver;
  p { text-align: center; text-transform: uppercase; font-family: "Gill Sans", Helvetica, sans-serif; }
  a { color: #444 }
}