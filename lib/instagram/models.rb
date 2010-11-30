require 'yajl/json_gem'
require 'nibbler/json'

module Instagram
  
  class Base < NibblerJSON
    element 'pk' => :id
  end
  
  class User < Base
    element :username
    element :full_name
    element 'profile_pic_url' => :avatar
    
    # extended info
    element :media_count
    element 'following_count' => :following
    element 'follower_count' => :followers
    
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
    element :code
    element :media_type
    element :filter_type
    element :device_timestamp
    element :taken_at, :with => lambda { |sec| Time.at(sec) }
    element :user, :with => User
    
    elements :likers, :with => User
    
    elements :comments, :with => NibblerJSON do
      element :created_at, :with => lambda { |sec| Time.at(sec) }
      element :content_type
      element :type
      element :media_id
      element :text
      element :user, :with => User
    end
    
    elements 'image_versions' => :images, :with => NibblerJSON do
      element :url
      element :type
      element :width
      element :height
      
      alias to_s url
    end
    
    def caption
      # a bit of guesswork
      if comments.first and self.user == comments.first.user
        comments.first.text
      end
    end
    
    def image_url(size = 150)
      self.images.find { |img| img.width == size }.to_s
    end
  end
  
  class Timeline < NibblerJSON
    elements :items, :with => Media
    # return items instead of self when done
    def parse() super.items end
  end
  
end