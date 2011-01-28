require 'yajl/json_gem'
require 'nibbler/json'

module Instagram
  
  class Base < NibblerJSON
    # `pk` is such a dumb property name
    element 'pk' => :id
  end
  
  class User < Base
    element :username
    element :full_name
    element 'profile_pic_url' => :avatar_url
    alias avatar avatar_url # `avatar` is deprecated
    
    # extended info
    element :media_count
    element :following_count
    alias following following_count # `following` will return an array of users in future!
    element :follower_count
    alias followers follower_count # `followers` will return an array of users in future!
    
    def ==(other)
      User === other and other.id == self.id
    end
  end
  
  class UserWrap < NibblerJSON
    element :user, :with => User
    # return user instead of self when done
    def parse() super.user end
  end
  
  class Media < Base
    # short string used for permalink
    element :code
    # type is always 1 (other values possibly reserved for video in the future?)
    element :media_type
    # filter code; use `filter_name` to get human name of the filter used
    element :filter_type
    # I don't know what "device timestamp" is and how it relates to `taken_at`?
    element :device_timestamp
    # timestamp of when the picture was taken
    element :taken_at, :with => lambda { |sec| Time.at(sec) }
    # user who uploaded the media
    element :user, :with => User
    
    # array of people who liked this media
    elements :likers, :with => User
    # user IDs of people who liked this (only if "likers" are not present)
    element :liker_ids
    
    elements :comments, :with => NibblerJSON do
      element :created_at, :with => lambda { |sec| Time.at(sec) }
      # content type is always "comment"
      element :content_type
      # `type` is always 1 (other values possibly reserved for comments in form of media?)
      element :type
      # the `pk` of parent media
      element :media_id
      # comment body
      element :text
      # comment author
      element :user, :with => User
    end
    
    elements 'image_versions' => :images, :with => NibblerJSON do
      element :url
      # `type` is 5 for 150px, 6 for 306px and 7 for 612px
      element :type
      element :width
      element :height
      
      alias to_s url
    end
    
    # image location
    element :lat
    element :lng
    
    def geolocated?
      self.lat and self.lng
    end
    
    element :location, :with => Base do
      # ID on a 3rd-party service
      element :external_id
      # name of 3rd-party service, like "foursquare"
      element :external_source
      # name of location
      element :name
      # address in the external service's database
      element :address
      element :lat
      element :lng
    end
    
    # author's caption for the image; can be nil
    def caption
      # caption is implemented as a first comment made by the owner
      if comments.first and self.user == comments.first.user
        comments.first.text
      end
    end
    
    # typical sizes: 150px / 306px / 612px square
    def image_url(size = 150)
      self.images.find { |img| img.width == size }.to_s
    end
    
    FILTERS = {
      1 => 'X-Pro II',
      2 => 'Lomo-fi',
      3 => 'Earlybird',
      4 => 'Apollo',
      5 => 'Poprocket',
      10 => 'Inkwell',
      13 => 'Gotham',
      14 => '1977',
      15 => 'Nashville',
      16 => 'Lord Kelvin',
      17 => 'Lily',
      18 => 'Sutro',
      19 => 'Toaster',
      20 => 'Walden',
      21 => 'Hefe'
    }
    
    def filter_name
      FILTERS[filter_type.to_i]
    end
  end
  
  class Tag < String
    attr_reader :media_count
    
    def initialize(str, count)
      super(str)
      @media_count = count
    end
    
    def self.parse(hash)
      new hash['name'], hash['media_count']
    end
    
    def inspect
      "#{super} (#{media_count})"
    end
  end
  
  class SearchTagsResults < NibblerJSON
    elements :results, :with => Tag
    def parse() super.results end
  end
  
  class Timeline < NibblerJSON
    elements :items, :with => Media
    # return items instead of self when done
    def parse() super.items end
  end
  
end