require 'addressable/uri'
require 'addressable/template'
require 'net/http'
require 'instagram/models'

module Instagram
  
  extend self
  
  Popular = Addressable::URI.parse 'http://instagr.am/api/v1/feed/popular/'
  UserFeed = Addressable::Template.new 'http://instagr.am/api/v1/feed/user/{user_id}/'
  UserInfo = Addressable::Template.new 'http://instagr.am/api/v1/users/{user_id}/info/'
  
  def popular(params = {})
    parse_response(Popular.dup, params, Timeline)
  end
  
  def by_user(user_id, params = {})
    url = UserFeed.expand :user_id => user_id
    parse_response(url, params, Timeline)
  end
  
  def user_info(user_id, params = {})
    url = UserInfo.expand :user_id => user_id
    parse_response(url, params, UserWrap)
  end
  
  private
  
  def parse_response(url, params, parser)
    url.query_values = params
    body = get_url url
    parser.parse body
  end
  
  def get_url(url)
    response = Net::HTTP.get_response url
    
    if Net::HTTPSuccess === response
      response.body
    else
      response.error!
    end
  end
  
end
