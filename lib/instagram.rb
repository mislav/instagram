require 'addressable/uri'
require 'addressable/template'
require 'net/http'
require 'instagram/models'

module Instagram
  
  extend self
  
  Popular = Addressable::URI.parse 'http://instagr.am/api/v1/feed/popular/'
  UserFeed = Addressable::Template.new 'http://instagr.am/api/v1/feed/user/{user_id}/'
  UserInfo = Addressable::Template.new 'http://instagr.am/api/v1/users/{user_id}/info/'
  SearchTags = Addressable::Template.new "http://instagr.am/api/v1/tags/search/"
  Search = Addressable::Template.new "http://instagr.am/api/v1/feed/tag/{tag}/"
  
  def popular(params = {}, options = {})
    parse_response(Popular.dup, params, options.fetch(:parse_with, Timeline))
  end
  
  def by_user(user_id, params = {}, options = {})
    url = UserFeed.expand :user_id => user_id
    parse_response(url, params, options.fetch(:parse_with, Timeline))
  end
  
  def user_info(user_id, params = {}, options = {})
    url = UserInfo.expand :user_id => user_id
    parse_response(url, params, options.fetch(:parse_with, UserWrap))
  end
  
  def tags(query, params = {}, options = {})
    url = SearchTags.expand({})
    options[:q] = query
    parse_response(url, options, options.fetch(:parse_with, TagSearch))
  end
  
  def by_tag(tag, params = {}, options = {})
    url = Search.expand :tag => tag
    parse_response(url, params, options.fetch(:parse_with, Timeline))
  end
  
  private
  
  def parse_response(url, params, parser = nil)
    url.query_values = params
    body = get_url url
    parser ? parser.parse(body) : body
  end
  
  def get_url(url)
    response = Net::HTTP.start(url.host, url.port) { |http|
      http.get url.request_uri, 'User-agent' => 'Instagram Ruby client'
    }
    
    if Net::HTTPSuccess === response
      response.body
    else
      response.error!
    end
  end
  
end
