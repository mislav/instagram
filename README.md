# The original Instagram website and API client

This was the first web app that displayed profiles of Instagram users online. It
was done by using Instagrams private API. Despite the fact that Instagram now
displays user profiles on their official site, [this app is still online][web].

The process of sniffing out their private API is described in my post:
[Creating the missing Instagram web interface][story].

Nowadays [Instagram has an official API][official] and many 3rd-party web sites
that do interesting things with people's photos and data.

## The code

* The app is mostly contained in a single file: [`app.rb`][app]
* The lightweight Ruby API client it is using: [`instagram.rb`][client]
* The legacy API client (**not to be used**) is in `lib/`.


[web]: http://instagram.heroku.com
[official]: http://instagram.com/developer/
[story]: http://mislav.uniqpath.com/2010/12/instagram-web/
[app]: https://github.com/mislav/instagram/blob/master/app.rb
[client]: https://github.com/mislav/instagram/blob/master/instagram.rb
