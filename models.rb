require 'mingo'
require 'active_support/memoizable'
require 'indextank'
require 'will_paginate/finders/base'

class User < Mingo
  property :user_id
  property :username
  property :twitter
  property :twitter_id
  
  extend ActiveSupport::Memoizable
  
  class NotFound < RuntimeError; end
  
  def self.lookup(id)
    if id =~ /\D/
      first(username: id) or raise NotFound
    else
      self[id]
    end
  end
  
  def self.[](id)
    (first(user_id: id.to_i) || new(user_id: id.to_i)).tap do |user|
      unless user.username
        user.username = user.instagram_info.username
        user.save
      end
    end
  end
  
  def self.find_by_instagram_url(url)
    id = Instagram::Cached.discover_user_id(url)
    self[id] if id
  end
  
  def instagram_info
    Instagram::Cached::user_info self.user_id
  end
  memoize :instagram_info
  
  def photos(max_id = nil, raw = false)
    feed_params = max_id ? { max_id: max_id.to_s } : {}
    options = raw ? { parse_with: nil } : {}
    Instagram::Cached::by_user(self.user_id, feed_params, options)
  end
end

# mimics Instagram::Media
class IndexedPhoto < Struct.new(:id, :caption, :thumbnail_url, :large_url, :username, :taken_at, :filter_name)
  Fields = 'text,thumbnail_url,username,timestamp,big,filter'

  class << self
    include WillPaginate::Finders::Base

    protected

    def wp_query(query_options, pager, args, &block)
      query = args.first
      filter = query_options.delete(:filter)
      query = "#{query} AND filter:#{filter}" if filter

      params = {:len => pager.per_page, :start => pager.offset, :fetch => Fields}.update(query_options)
      data = ActiveSupport::Notifications.instrument('search.indextank', {:query => query}.update(params)) do
        search_index.search(query, params)
      end
      pager.total_entries = data['matches']
      pager.replace data['results'].map { |item| new item }
    end

    def search_index
      Sinatra::Application.settings.search_index
    end
  end

  self.per_page = 32

  def initialize(hash)
    super hash['docid'], hash['text'], hash['thumbnail_url'], hash['big'],
          hash['username'], Time.at(hash['timestamp'].to_i), hash['filter']
  end

  def image_url(size)
    case size
    when 612 then large_url
    when 150 then thumbnail_url
    end
  end

  User = Struct.new(:id, :full_name, :username)

  def user
    @user ||= User.new(nil, nil, username)
  end
end
