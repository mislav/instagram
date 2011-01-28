require 'addressable/uri'
require 'addressable/template'
require 'net/http'
require 'instagram/models'

module Instagram
  
  extend self
  
  Popular = Addressable::URI.parse 'http://instagr.am/api/v1/feed/popular/'
  UserFeed = Addressable::Template.new 'http://instagr.am/api/v1/feed/user/{user_id}/'
  UserInfo = Addressable::Template.new 'http://instagr.am/api/v1/users/{user_id}/info/'
  SearchTags = Addressable::URI.parse 'http://instagr.am/api/v1/tags/search/'
  TagFeed = Addressable::Template.new 'http://instagr.am/api/v1/feed/tag/{tag}/'
  
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
  
  def search_tags(query, params = {}, options = {})
    params = {:q => query}.merge(params)
    parse_response(SearchTags.dup, params, options.fetch(:parse_with, SearchTagsResults))
  end
  
  def by_tag(tag, params = {}, options = {})
    url = TagFeed.expand :tag => tag
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
