path = require('path')
fs = require('graceful-fs')
url = require('url')
i18n = require('i18n')
_ = require('underscore')
async = require('async')
mkdirp = require('mkdirp')

class I18nMiddleware

  constructor: (options) ->
    @options = _.extend(
      defaultLocale: 'en'
      cookie: 'lang'
      directory: "#{process.cwd()}/src/locales"
      src: "#{process.cwd()}/src"
      tmp: "#{process.cwd()}/tmp/i18n"
      grepExts: /(\.js|\.html)$/
      testExts: ['.coffee', '.html']
      pattern: /\{\{__([\s\S]+?)\}\}/g
      force: false
      updateFiles: false
      options or {}
    )
    unless @options.locales
      try
        langFiles = fs.readdirSync(@options.directory)
        @options.locales = (f[..f.length-path.extname(f).length-1] for f in langFiles)
      catch
        @options.locales = []
    i18n.configure(@options)
    @i18n = i18n

  # ops: filePath, destPath, lang
  compile: (ops, callback = ->) ->
    options = @options
    ops = ops

    _compile = ->
      fs.readFile ops.filePath, 'utf8', (err, content) ->
        return callback() if err?  # file missing
        content = content.replace options.pattern or /$^/, (m, code) ->
          result = i18n.__({phrase: code, locale: ops.lang})
          return result or code

        mkdirp path.dirname(ops.destPath), '0755', (err) ->
          return callback() if err?
          fs.writeFile(ops.destPath, content, 'utf8', callback)

    return _compile() if options.force

    fs.stat ops.filePath, (err, srcStat) ->
      return callback() if err?
      fs.stat ops.destPath, (err, destStat) ->
        if err
          if err.code is 'ENOENT'
            _compile()
          else
            return callback()
        else
          if srcStat.mtime > destStat.mtime
            _compile()
          else
            callback()

  _guessLanguage: (req, res, next) ->
    languageHeader = req.headers['accept-language']
    languages = []
    if languageHeader?
      languageHeader.split(',').every (l) =>
        lang = l.split(';')[0]
        subLang = lang.split('-')[0]
        if lang in @options.locales
          @options.defaultLocale = lang
          return false
        if subLang in @options.locales
          @options.defaultLocale = lang
          return false
        return true
    next()

  middleware: ->
    options = @options

    _middleware = (req, res, next) =>
      i18n.init req, res, =>
        @_guessLanguage req, res, =>
          lang = i18n.getLocale(req)
          lang = if lang in options.locales then lang else @options.defaultLocale
          lang = lang or 'en'

          i18n.setLocale(req, lang)

          pathname = url.parse(req.url).pathname
          tmpPath = "#{options.tmp}/#{lang}"

          if matches = pathname.match(options.grepExts)

            async.each options.testExts, ((_ext, _next) =>
              fileRelPath = pathname.replace(options.grepExts, _ext)
              filePath = path.join(options.src, fileRelPath)
              destPath = "#{options.tmp}/#{lang}#{fileRelPath}"

              _options = {
                filePath: filePath
                destPath: destPath
                lang: lang
              }

              @compile(_options, _next)

              ), (err) ->
              next()
          else
            next()

    return _middleware

i18nMiddleware = (options) ->
  middleware = new I18nMiddleware(options)
  @options = middleware.options
  return middleware.middleware()

i18nMiddleware.I18nMiddleware = I18nMiddleware

i18nMiddleware.version = '0.0.1'

module.exports = i18nMiddleware