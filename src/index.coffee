'use strict'

# TODO: Cache changed files, and enqueue tasks after ~ 300 ms
#       The queue should only processed if there is no current task chain running
#       (there is currently a problem if heavy folder renaming takes place!)

PLUGIN_NAME = 'gulp-watch-network'

net         = require 'net'
path        = require 'path'

_           = require 'lodash'
minimatch   = require 'minimatch'
touch       = require 'touch'
chalk       = require 'chalk'
runSequence = require 'run-sequence'
fs          = require 'fs'
gutil       = require 'gulp-util'
util        = require 'util'


{EventEmitter} = require 'events'

defaultOptions =
  host: 'localhost'
  port: 4000
  rootFile: '.root'
  onLoad: false
  configs: []


class WatchNetwork extends EventEmitter

  constructor: (@_options = {}) ->
    _.defaults @_options, defaultOptions

    if @_options.gulp
      runSequence = runSequence.use @_options.gulp

    @_localRootFilePath = path.join process.cwd(), @_options.rootFile
    @_localDir = process.cwd()
    @_rootPath = null
    @_waitingOnRootFileChange = true
    @_waitingOnRootFileChangeRetries = 0
    @_waitingOnRootFileChangeMaxRetries = 3
    @_waitingOnRootFileChangeIntervalId = null
    @_initialized = false


  initialize: (callback) ->
    gutil.log "Initializing"
    @_removeLocalRootFile()

    socket = @_connectToSocket =>
      gutil.log "Connected to Listen at #{@_options.host}:#{@_options.port}"

    socket.on 'data', =>
      gutil.log "Receiving Data from Listen"
      @_handleIncomingDataFromListen arguments...

    socket.on 'end', =>
      gutil.log "Connection to Listen lost"

    @_executeOnLoadTasks()

    process.on 'SIGINT', =>
      socket.destroy()
      gutil.log "Disconnected from Listen"
      process.exit 0

    @on 'initialized', ->
      callback()


  _removeLocalRootFile: ->
    if fs.existsSync @_localRootFilePath
      fs.unlinkSync @_localRootFilePath


  _connectToSocket: (callback) ->
    net.connect
      port: @_options.port
      host: @_options.host
    , =>
      callback.apply arguments...
      @_touchLocalRootFileAndRetry.apply arguments...


  _touchLocalRootFileAndRetry: =>
    @_waitingOnRootFileChangeIntervalId = setInterval =>
      if not @_waitingOnRootFileChange
        return


      if @_waitingOnRootFileChangeRetries > @_waitingOnRootFileChangeMaxRetries
        err = "No change event after touching the RootFile, aborting..
              (max retries reached: #{@_waitingOnRootFileChangeMaxRetries})"
        gutil.log err
        throw new Error err

      @_touchLocalRootFile()

      retries = ""
      if @_waitingOnRootFileChangeRetries > 0
        retries = "Retries (#{@_waitingOnRootFileChangeRetries}/#{@_waitingOnRootFileChangeMaxRetries})"
      gutil.log "Waiting for incoming Listen Data..#{retries}"

      @_waitingOnRootFileChangeRetries++
    , 500


  _touchLocalRootFile: ->
    gutil.log "Touching Local RootFile #{@_localRootFilePath}"
    touch.sync @_localRootFilePath


  _handleIncomingDataFromListen: (buffer, callback) =>
    json  = @_parseJsonFromListenData buffer
    files = @_convertListenJsonToArray json

    if @_waitingOnRootFileChange
      @_waitingOnRootFileChange = false
      clearInterval @_waitingOnRootFileChangeIntervalId
      @_searchRootFileInChangedFilesAndRetry files, =>
        files = @_stripRootPathFromFiles files
        @emit 'changed', files
        @_executeTasks files

    else
      files = @_stripRootPathFromFiles files
      gutil.log "Files changed: #{files.join(', ')}"
      @emit 'changed', files
      @_executeTasks files


  _searchRootFileInChangedFilesAndRetry: (files, callback) ->
    maxRetries = 3
    i = 0
    while (true)
      i++
      if i > maxRetries
        err = "Couldnt find the RootFile in the Changed Files, aborting.. (max retries reached: #{maxRetries})"
        gutil.log err
        throw new Error err

      found = @_searchRootFileInChangedFiles files
      if not found
        gutil.log "Couldnt find the RootFile in the Changed Files, retrying.. #{i}/#{maxRetries}"
        @_waitingOnRootFileChange = true
        @_touchLocalRootFile()
      else
        @emit 'initialized'
        @_initialized = true
        callback()
        break


  _searchRootFileInChangedFiles: (files) ->
    if @_rootPath
      return true

    rootFileRegExp = new RegExp "#{@_options.rootFile}$"
    gutil.log "Got FileChange Events from Listen, scanning for the RootFile #{@_localRootFilePath}"

    rootFileRelativePathToRootDir = path.relative @_localRootFilePath, process.cwd()
    for filename in files
      if not rootFileRegExp.test filename
        continue

      @_rootPath = path.join filename, rootFileRelativePathToRootDir
      gutil.log 'Successfully detected RootFile!'
      gutil.log "Local: #{@_localDir} - Remote: #{@_rootPath}"
      return true

    if not @_rootPath
      return false


  _parseJsonFromListenData: (buffer) ->
    json = buffer.toString()
    json = json.match(/\{[\s\S]*\}/)[0]
    json = JSON.parse json


  _convertListenJsonToArray: (json) ->
    _.union json.modified, json.added, json.removed


  _stripRootPathFromFiles: (files) ->
    remoteDirRegExp = new RegExp "#{@_rootPath}/?"
    files = files.map (file) =>
      file.replace remoteDirRegExp, ''


  _executeTasks: (files) ->
    rootFileRelativePathToRootDir = path.relative @_localRootFilePath, process.cwd()
    for filename in files
      @_executeTasksBasedOnPatterns filename.replace "#{@_rootPath}/", ''


  _executeOnLoadTasks: ->
    for config in @_options.configs
      if config.onLoad
        @_executeTasksWithRunSequence config.async, config.tasks


  _executeTasksBasedOnPatterns: (filename) ->
    for config in @_options.configs
      continue if not config.patterns or not config.tasks
      # Ensure array
      patterns = _.flatten [config.patterns]
      for pattern in patterns
        if minimatch filename, pattern
          @_executeTasksWithRunSequence config.async, config.tasks


  _executeTasksWithRunSequence: (async, tasks) ->
    gutil.log chalk.magenta "Execute GulpJs tasks \"#{tasks}\" - [async: #{!!async}]"
    finshedTasks = ->
      gutil.log chalk.magenta "Finished GulpJs tasks \"#{tasks}\" - [async: #{!!async}]"

    # Ensure array
    tasks = _.flatten [tasks]

    if async
      runSequence tasks, finshedTasks
    else
      clonedTasks = _.clone tasks
      clonedTasks.push finshedTasks
      runSequence.apply runSequence, clonedTasks


module.exports = (options) ->
  new WatchNetwork options
