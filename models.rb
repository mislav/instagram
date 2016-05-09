require 'mingo'
require 'will_paginate/collection'
require 'hashie/mash'
require 'net/http'
require 'forwardable'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/time/acts_like'

class User < Mingo
  property :user_id
  property :username
  property :twitter
  property :twitter_id
  property :error_at
  property :error_type

  extend Forwardable
  def_delegators :'instagram_info.data', :profile_picture, :full_name, :counts

  class NotAvailable < RuntimeError
    attr_reader :user
    def initialize user
      super "response for user #{user.user_id} was #{user.error_type}"
      @user = user
    end
  end

  class << self
    attr_accessor :blacklist

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

      user = nil if blacklist && blacklist.call(user)
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
    @instagram_info ||= record_error Instagram::user(self.user_id)
  end
  
  def photos(max_id = nil, raw = false)
    raise_if_recent_error
    params = { count: 20 }
    params[:max_id] = max_id.to_s if max_id
    params[:raw] = raw if raw
    response = Instagram::user_recent_media(self.user_id, params)
    record_error response, :raise_immediately
  end

  def private_account?
    'APINotAllowedError' == error_type or self[:private]
  end

  def private!
    self[:private] = true
    save
    self
  end

  def account_removed?
    'APINotFoundError' == error_type
  end

  private

  def not_available!
    raise NotAvailable, self
  end

  def raise_if_recent_error
    not_available! if private_account? or (error_at and error_at > 1.day.ago)
  end

  def record_error(response, do_raise = false)
    if 400 == response.status and response.is_a? Hash
      self.error_at = Time.now
      self.error_type = response['meta']['error_type']
      self.save if persisted?
      not_available! if do_raise
    elsif 200 == response.status
      self.error_at = nil
      self.error_type = nil
      self.save if persisted?
    end
    response
  end
end

module Instagram
  module Discovery
    def self.discover_user_id(url)
      url = URI.parse url unless url.respond_to? :host
      url.host = 'instagram.com' if url.host == 'instagr.am'
      $1.to_i if get_url(url) =~ %r{profiles/profile_(\d+)_}
    end
  
    LinkRe = %r{https?://t.co/[\w-]+}
    PermalinkRe = %r{https?://(instagr\.am|instagram\.com)/p/[\w-]+/?}
    TwitterSearch = URI.parse 'http://search.twitter.com/search.json'
    UserInfo = URI.parse 'http://api.twitter.com/1/users/show.json'
  
    def self.search_twitter(username)
      url = TwitterSearch.dup
      url.query = Rack::Utils.build_query q: "from:#{username} instagr.am"
      data = JSON.parse get_url(url)
      data['results'].each do |tweet|
        if tweet['text'] =~ LinkRe
          if (link = resolve_shortened($&)) =~ PermalinkRe
            user_id = tweet['user'] ? tweet['user']['id'] : twitter_user(username)['id'] rescue nil
            return [link, user_id]
          end
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
        url = URI.parse url unless url.respond_to? :host
        Net::HTTP.get_response(url)['location']
      end
      
      def get_url(url)
        Net::HTTP.get(url)
      end
    end
  end
end
