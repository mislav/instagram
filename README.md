# [Instagram][] Ruby library

This library acts as a client for the [unofficial Instagram API][wiki]. It was used to create [the missing Instagram web interface][web].

    $ gem install instagram

With it, you can:

* fetch popular photos;
* get user info;
* browse photos by a user.

Caveat: you need to know user IDs; usernames can't be used. However, you can start from the popular feed and drill down from there.

## Example usage

    require 'instagram'
    
    photos = Instagram::popular
    photo = photos.first
    
    photo.caption     #=> "Extreme dog closeup"
    photo.likes.size  #=> 54
    photo.filter_name #=> "X-Pro II"
    
    photo.user.username      #=> "johndoe"
    photo.user.full_name     #=> "John Doe"
    photo.comments[1].text   #=> "That's so cute"
    photo.images.last.width  #=> 612
    
    photo.image_url(612)
    # => "http://distillery.s3.amazonaws.com/media/-.jpg"
    
    # fetch extended info for John
    john_info = Instagram::user_info(photo.user.id)
    
    john_info.media_count    #=> 32
    john_info.follower_count #=> 160
    
    
    # find more photos by John
    photos_by_john = Instagram::by_user(photo.user.id)


## Credits

Instagram API documentation and Ruby library written by Mislav Marohnić.


[instagram]: http://instagr.am/
[web]: http://instagram.heroku.com
[wiki]: https://github.com/mislav/instagram/wiki "Instagram API"