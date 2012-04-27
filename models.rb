require 'mingo'
require 'will_paginate/collection'
require 'hashie/mash'
require 'net/http'
require 'forwardable'

class User < Mingo
  property :user_id
  property :username
  property :twitter
  property :twitter_id

  extend Forwardable
  def_delegators :'instagram_info.data', :profile_picture, :full_name, :counts

  class << self
    def lookup(id)
      unless user = find_by_username_or_id(id) or id =~ /\D/
        # lookup Instagram user by ID
        user = new(user_id: id.to_i)
        if 200 == user.instagram_info.status
          user.username = user.instagram_info.data.username
          user.save
        else
          user = nil
        end
      end

      user || (block_given? ? yield : nil)
    end
    alias [] lookup

    private

    def id_selector(id)
      id =~ /\D/ ? {username: id} : {user_id: id.to_i}
    end
  end
  
  def self.delete(id)
    collection.remove id_selector(id)
  end
  
  def self.find_by_username_or_id(id)
    first(id_selector(id))
  end
  
  def self.find_by_user_id(user_id)
    find_by_username_or_id(user_id.to_i)
  end
  
  def self.find_or_create_by_user_id(id)
    user = find_by_user_id(id) || new(user_id: id.to_i)
    if block_given?
      user.save unless yield(user) == false
    end
    user
  end

  def self.from_token(token)
    find_or_create_by_user_id(token.user.id) do |user|
      if user.username and user.username != token.user.username
        user['old_username'] = user.username
      end
      user.username = token.user.username
      user['access_token'] = token.access_token
    end
  end
  
  def self.find_by_instagram_url(url)
    id = Instagram::Discovery.discover_user_id(url)
    lookup(id) if id
  end
  
  def instagram_info
    @instagram_info ||= Instagram::user(self.user_id)
  end
  
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
      url = URI.parse url unless url.respond_to? :hostname
      $1.to_i if get_url(url) =~ %r{profiles/profile_(\d+)_}
    end
  
    LinkRe = %r{https?://t.co/[\w-]+}
    PermalinkRe = %r{https?://instagr\.am/p/[\w-]+/?}
    TwitterSearch = URI.parse 'http://search.twitter.com/search.json'
    UserInfo = URI.parse 'http://api.twitter.com/1/users/show.json'
  
    def self.search_twitter(username)
      url = TwitterSearch.dup
      url.query = Rack::Utils.build_query q: "from:#{username} instagr.am"
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
        url = URI.parse url unless url.respond_to? :hostname
        Net::HTTP.get_response(url)['location']
      end
      
      def get_url(url)
        Net::HTTP.get(url)
      end
    end
  end
end
