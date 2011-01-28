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

  function hashchange() {
    if (/#p([\w-]+)/.test(location.hash)) viewPhoto(RegExp.$1)
    else closePhoto()
  }

  function viewPhoto(item) {
    if (typeof item == "string") item = $('#media_' + item)
    if (!item.get(0) || item.hasClass('active')) return
    var thumb = item.find('.thumb')
    
    var photoDidLoad = function(img) {
      thumb.removeClass('loading')
      var container = $('#photos').addClass('lightbox')
      item.addClass('active').find('.full img').attr('src', img.src)
      location.hash = '#p' + item.attr('id').split('_')[1]
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

  $(window).bind('hashchange', hashchange)
  hashchange()

  $('#photos a.thumb').live('click', function(e) {
    e.preventDefault()
    this.blur()
    viewPhoto($(this).closest('li'))
  })

  $('#photos a[href="#close"], #photos .full img').live('click', function(e) {
    e.preventDefault()
    if (window.history.length > 1) window.history.back()
    else location.href = location.href.split('#')[0]
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