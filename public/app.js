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

var readyInterval

function ready(name, fn) {
  if (window[name]) {
    fn(window[name])
    return true
  }
  else if (!readyInterval) {
    readyInterval = setInterval(function() {
      if (ready(name, fn)) clearInterval(readyInterval)
    }, 50)
  }
  else return false
}

ready('$', function($) {
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
    
    $('input[placeholder], textarea[placeholder]')
      .bind('focusin', function(e) {
        var input = $(this)
        if (input.val() === input.attr('placeholder')) input.val('').removeClass('placeholder')
      })
      .bind('focusout', function(e) {
        emulatePlaceholder($(this))
      })
      .each(function() {
        emulatePlaceholder($(this))
      })
  }

  $('form').live('submit', function() {
    var select = $(this).find('select[name=filter]')
    if (select.get(0) && !select.get(0).selectedIndex) select.attr('disabled', 'disabled')
  })

  function viewPhoto(item) {
    if (typeof item == "string") item = $('#media_' + item)
    if (!item.get(0) || item.hasClass('active')) return
    var thumb = item.find('.thumb')
    
    var photoDidLoad = function(img) {
      thumb.removeClass('loading')
      var container = $('#photos').addClass('lightbox')
      item.addClass('active').find('.full img').attr('src', img.src)
      pushPhotoState(item.attr('id').split('_')[1])
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
        trackPageview(url + hash)
      }
    } else {
      if (history.pushState) {
        history.pushState({ photo: null, closed: true }, "", url)
        trackPageview(url)
      }
      else location.href = url
    }
  }

  function trackPageview(url) {
    if (url.indexOf('://') >= 0) url = url.split(/:\/\/[^\/]+/)[1]
    if (url.indexOf('?') < 0) url = url.replace('#p', '/p')
    if (window._gaq) _gaq.push(['_trackPageview', url])
    else if (window.console) console.log('trackPageview: ' + url)
  }

  function hashchange(e) {
    if (/#p([\w-]+)/.test(location.hash)) viewPhoto(RegExp.$1)
    else closePhoto()
  }

  if (history.pushState) {
    $(window).bind('popstate', function(e) {
      trackPageview(location.href)
      if (e.state && e.state.photo) viewPhoto(e.state.photo)
      else closePhoto()
    })
  } else {
    $(window).bind('hashchange', hashchange)
  }
  hashchange()

  $('#photos a.thumb').live('click', function(e) {
    e.preventDefault()
    this.blur()
    viewPhoto($(this).closest('li'))
  })

  $('#photos a[href="#close"], #photos .full img').live('click', function(e) {
    e.preventDefault()
    var url = location.href.split('#')[0]
    pushPhotoState(null)
    closePhoto()
  })

  $('#photos .pagination a').live('click', function(e) {
    e.preventDefault()
    $(this).find('span').text('Loading...')
    var item = $(this).closest('.pagination')
    $.get($(this).attr('href'), function(body) {
      item.remove()
      $('#photos').append(body)
    })
  })
})