var preloadCache = {}

function preload(src, fn) {
  var img = preloadCache[src] || new Image

  if (img.loaded) {
    if (fn) fn(img)
    return false
  }

  img.onload = function() {
    this.loaded = true
    if (fn) fn(this)
  }
  img.src = src
  preloadCache[src] = img
  return true
}

Zepto(function($) {
  var svg = $.browser && $.browser.webkit

  if (!svg) {
    $(document.body).addClass('no-svg')
    preload('/spinner.gif')
  }
  else preload('/spinner.svg')

  var input = document.createElement('input')
  input.setAttribute('type', 'search')
  if (input.type == 'text') $(document.body).addClass('no-inputsearch')

  if (!('placeholder' in input)) {
    function emulatePlaceholder(field) {
      var val = field.val(), text = field.attr('placeholder')
      if (!val || val === text) field.val(text).addClass('placeholder')
    }

    $('input[placeholder], textarea[placeholder]').on({
      focusin: function(e) {
        var input = $(this)
        if (input.val() === input.attr('placeholder')) input.val('').removeClass('placeholder')
      },
      focusout: function(e) {
        emulatePlaceholder($(this))
      }
    }).each(function(){ emulatePlaceholder($(this)) })
  }

  function viewPhoto(item) {
    if (typeof item == "string") item = $('*[id^="media_' + item + '"]')
    if (!item.get(0) || item.hasClass('active')) return
    var thumb = item.find('.thumb')
    
    var photoDidLoad = function(img) {
      thumb.removeClass('loading')
      var container = $('#photos').addClass('lightbox')
      item.addClass('active').find('.full img').attr('src', img.src)
      pushPhotoState(item.attr('id').replace(/\w+?_/, ''))
      if ($.os && $.os.iphone) scrollTo(0, container.offset().top - 8);
    }
    
    if (preload(thumb.attr('href'), photoDidLoad)) {
      thumb.addClass('loading')
    }
  }

  function closePhoto(item) {
    if (!$('#photos').hasClass('lightbox')) return
    if (!item) item = $('#photos li.active')
    item.removeClass('active')
    $('#photos').removeClass('lightbox')
  }

  function pushPhotoState(photoID) {
    var url = location.href.split('#')[0]
    if (photoID) {
      var hash = '#p' + photoID
      if (location.hash != hash) {
        if (history.pushState) history.pushState({ photo: photoID }, "", hash)
        else location.hash = hash
        trackPageview()
      }
    } else {
      if (history.pushState) {
        history.pushState({ photo: null, closed: true }, "", url)
        trackPageview()
      }
      else location.href = url
    }
  }

  function trackPageview() {
    if (window._gauges) _gauges.push(['track'])
    else if (window.console) console.log('trackPageview: ' + location.toString())
  }

  function hashchange(e) {
    if (/#p([\w-]+)/.test(location.hash)) viewPhoto(RegExp.$1)
    else closePhoto()
  }

  if (history.pushState) {
    setTimeout(function(){
      $(window).on('popstate', function(e) {
        trackPageview()
        if (e.state) {
          if (e.state.photo) viewPhoto(e.state.photo)
          else closePhoto()
        }
        else hashchange()
      })
    }, 1000) // http://code.google.com/p/chromium/issues/detail?id=63040#c11
  } else {
    $(window).on('hashchange', hashchange)
  }
  hashchange()

  $('#photos')
    .on('click', 'a.thumb', function(e){
      e.preventDefault()
      try { this.blur() } catch(e) { }
      viewPhoto($(this).closest('li'))
    })
    .on('click', 'a[href="#close"], .full img', function(e){
      e.preventDefault()
      var url = location.href.split('#')[0]
      pushPhotoState(null)
      closePhoto()
    })
    .on('click', '.pagination a', function(e){
      e.preventDefault()
      $(this).find('span').text('Loading...')
      var item = $(this).closest('.pagination')
      $.get($(this).attr('href'), function(body) {
        item.remove()
        $('#photos').append(body)
      })
    })
})
