# encoding: utf-8
require 'sinatra'
require 'active_support/cache'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/time/acts_like'
require 'instagram'
require 'haml'

set :haml, format: :html5

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
end

get '/' do
  @photos = CachedInstagram::popular
  @title = "Instagram popular items"
  
  expires 30.minutes, :public
  haml :index
end

get '/users/:id' do
  unless xhr?
    @user = CachedInstagram::user_info params[:id]
    @title = "Photos by #{@user.username} on Instagram"
  end
  
  feed_params = params[:max_id] ? { max_id: params[:max_id].to_s } : {}
  @photos = CachedInstagram::by_user(params[:id], feed_params)
  
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
    $(this).text('Loading...')
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
    %a{ href: request.path + "?max_id=#{@photos.last.id}" } Load more &rarr;

@@ style
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
  li {
    display: inline;
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
      text-align: center;
      a {
        margin-left: 1em;
        font-size: 80%; padding: .2em .6em;
        color: white; background: #bbb; text-decoration: none;
        text-shadow: rgba(0,0,0,.4) 1px 1px 1px;
        position: relative; top: -10px;
      }
      a:hover { background: #999 }
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