require 'addressable/uri'
require 'addressable/template'
require 'net/http'
require 'instagram/models'

module Instagram
  
  Popular = Addressable::URI.parse 'http://instagr.am/api/v1/feed/popular/'
  UserFeed = Addressable::Template.new 'http://instagr.am/api/v1/feed/user/{user_id}/'
  UserInfo = Addressable::Template.new 'http://instagr.am/api/v1/users/{user_id}/info/'
  
  def self.popular(params = {})
    url = Popular.dup
    parse_response(url, params, Timeline)
  end
  
  def self.by_user(user_id, params = {})
    url = UserFeed.expand :user_id => user_id
    parse_response(url, params, Timeline)
  end
  
  def self.user_info(user_id, params = {})
    url = UserInfo.expand :user_id => user_id
    parse_response(url, params, UserWrap)
  end
  
  def self.parse_response(url, params, parser)
    url.query_values = params
    body = Net::HTTP.get url
    parser.parse body
  end
  
end
