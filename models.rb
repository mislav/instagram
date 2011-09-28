require 'mingo'
require 'active_support/memoizable'
require 'indextank'
require 'will_paginate/collection'
require 'hashie/mash'
require 'net/http'

class User < Mingo
  property :user_id
  property :username
  property :twitter
  property :twitter_id
  
  extend ActiveSupport::Memoizable
  
  class NotFound < RuntimeError; end
  
  class << self
    def lookup(id)
      if id =~ /\D/
        first(username: id)
      else
        find_by_user_id(id)
      end or raise NotFound
    end
    alias [] lookup
  end
  
  def self.delete(id)
    selector = id =~ /\D/ ? {username: id} : {user_id: id.to_i}
    collection.remove(selector)
  end
  
  def self.find_by_user_id(user_id)
    first(user_id: user_id.to_i)
  end
  
  def self.find_or_create_by_user_id(id)
    (first(user_id: id.to_i) || new(user_id: id.to_i)).tap do |user|
      unless user.username
        user.username = user.instagram_info.username
        user.save
      end
    end
  rescue NoMethodError
    new(user_id: id.to_i)
  end

  def self.from_token(token)
    id = token.user.id
    (first(user_id: id.to_i) || new(user_id: id.to_i)).tap do |user|
      if user.username and user.username != token.user.username
        user['old_username'] = user.username
      end
      user.username = token.user.username
      user['access_token'] = token.access_token
      user.save
    end
  end
  
  def self.find_by_instagram_url(url)
    id = Instagram::Discovery.discover_user_id(url)
    find_or_create_by_user_id(id) if id
  end
  
  def instagram_info
    Instagram::user(self.user_id)
  end
  memoize :instagram_info
  
  def photos(max_id = nil, raw = false)
    params = { count: 20 }
    params[:max_id] = max_id.to_s if max_id
    params[:raw] = raw if raw
    Instagram::user_recent_media(self.user_id, params)
  end
end

module Instagram
  module Discovery
    def self.discover_user_id(url)
      url = Addressable::URI.parse url unless url.respond_to? :host
      $1.to_i if get_url(url) =~ %r{profiles/profile_(\d+)_}
    end
  
    LinkRe = %r{https?://t.co/[\w-]+}
    PermalinkRe = %r{https?://instagr\.am/p/[\w-]+/?}
    TwitterSearch = Addressable::URI.parse 'http://search.twitter.com/search.json'
    UserInfo = Addressable::URI.parse 'http://api.twitter.com/1/users/show.json'
  
    def self.search_twitter(username)
      url = TwitterSearch.dup
      url.query_values = { q: "from:#{username} instagr.am" }
      data = JSON.parse get_url(url)
      data['results'].each do |tweet|
        if tweet['text'] =~ LinkRe and resolve_shortened($&) =~ PermalinkRe
          link = $&
          user_id = tweet['user'] ? tweet['user']['id'] : twitter_user(username)['id'] rescue nil
          return [link, user_id]
        end
      end
      return nil
    end

    class << self
      private
      
      def twitter_user(username)
        user_info = UserInfo.dup
        user_info.query_values = {screen_name: username, include_entities: 'false'}
        JSON.parse get_url(user_info)
      end
      
      def resolve_shortened(url)
        url = Addressable::URI.parse url unless url.respond_to? :host
        Net::HTTP.get_response(url)['location']
      end
      
      def get_url(url)
        Net::HTTP.get(url)
      end
    end
  end
end

# mimics Instagram::Media
class IndexedPhoto < Struct.new(:id, :caption, :thumbnail_url, :large_url, :username, :taken_at, :filter_name)
  Fields = 'text,thumbnail_url,username,timestamp,big,filter'

  extend WillPaginate::PerPage

  self.per_page = 32

  def self.paginate(query, options)
    options = options.dup
    page = WillPaginate::PageNumber(options.fetch(:page) || 1)
    per_page = options.delete(:per_page) || self.per_page
    filter = options.delete(:filter)
    query = "#{query} AND filter:#{filter}" if filter

    WillPaginate::Collection.create(page, per_page) do |col|
      params = {:len => col.per_page, :start => col.offset, :fetch => Fields}.update(options)
      data = ActiveSupport::Notifications.instrument('search.indextank', {:query => query}.update(params)) do
        search_index.search(query, params)
      end
      col.total_entries = data['matches']
      col.replace data['results'].map { |item| new item }
    end
  end

  def self.search_index
    Sinatra::Application.settings.search_index
  end

  def initialize(hash)
    super hash['docid'], hash['text'], hash['thumbnail_url'], hash['big'],
          hash['username'], Time.at(hash['timestamp'].to_i), hash['filter']
  end

  User = Struct.new(:id, :full_name, :username)
  Caption = Struct.new(:text)

  def user
    @user ||= User.new(nil, nil, username)
  end
  
  def caption
    if text = super
      @caption ||= Caption.new(text)
    end
  end
  
  def images
    @images ||= Hashie::Mash.new \
      thumbnail: { url: thumbnail_url, width: 150, height: 150 },
      standard_resolution: { url: large_url, width: 612, height: 612 }
  end
end
