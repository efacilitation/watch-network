'use strict'

# TODO: Cache changed files, and enqueue tasks after ~ 300 ms
#       The queue should only processed if there is no current task chain running
#       (there is currently a problem if heavy folder renaming takes place!)

PLUGIN_NAME = 'gulp-watch-network'

async       = require 'async'
net         = require 'net'
path        = require 'path'

_           = require 'lodash'
minimatch   = require 'minimatch'
touch       = require 'touch'
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
    @_executingTasks = false
    @_deferredTasks = []
    @_waitingOnRootFileChange = true
    @_waitingOnRootFileChangeRetries = 0
    @_waitingOnRootFileChangeMaxRetries = 3
    @_waitingOnRootFileChangeIntervalId = null
    @_initialized = false

    @lastChangeTime = null
    @on 'changed', =>
      @lastChangeTime = new Date()



  initialize: (callback = ->) ->
    gutil.log "Initializing"
    @on 'initialized', ->
      callback()

    gutil.log "Executing Tasks with onLoad flag"
    @_executeTasksOnLoad =>

      gutil.log "Connecting to Listen"
      socket = @_connectToSocket =>
        gutil.log "Connected to Listen at #{@_options.host}:#{@_options.port}"

      socket.on 'data', =>
        gutil.log "Receiving Data from Listen"
        @_handleIncomingDataFromListen arguments...

      socket.on 'end', =>
        gutil.log "Connection to Listen lost"

    process.on 'SIGINT', =>
      socket.destroy()
      gutil.log "Disconnected from Listen"
      process.exit 0


  _connectToSocket: (callback) ->
    net.connect
      port: @_options.port
      host: @_options.host
    , =>
      callback.apply arguments...
      @_touchLocalRootFileAndWait.apply arguments...


  _touchLocalRootFileAndWait: =>
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


  _handleIncomingDataFromListen: (buffer, callback = ->) =>
    json  = @_parseJsonFromListenData buffer
    files = @_convertListenJsonToArray json

    if @_waitingOnRootFileChange
      @_waitingOnRootFileChange = false
      clearInterval @_waitingOnRootFileChangeIntervalId
      @_searchRootFileInChangedFilesAndWait files, =>
        files = @_stripRootPathFromFiles files
        @emit 'changed', files
        callback()

    else
      files = @_stripRootPathFromFiles files
      gutil.log "Files changed: #{files.join(', ')}"
      @emit 'changed', files
      @_executeTasksMatchingChangedFiles files, callback


  _searchRootFileInChangedFilesAndWait: (files, callback) ->
    maxRetries = 3
    retry = 0
    while (true)
      found = @_searchRootFileInChangedFiles files
      if found
        @_removeLocalRootFile()
        @emit 'initialized'
        @_initialized = true
        callback()
        break

      else
        retry++
        if retry <= maxRetries
          gutil.log "Couldnt find the RootFile in the Changed Files, retrying.. #{retry}/#{maxRetries}"
        else
          err = "Couldnt find the RootFile in the Changed Files, aborting.. (max retries reached: #{maxRetries})"
          gutil.log err
          throw new Error err

        @_waitingOnRootFileChange = true
        @_removeLocalRootFile()
        @_touchLocalRootFileAndWait()


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


  _removeLocalRootFile: ->
    if fs.existsSync @_localRootFilePath
      fs.unlinkSync @_localRootFilePath


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


  _executeTasksOnLoad: (callback = ->) ->
    async.eachSeries @_options.configs, (config, done) ->
      if config.onLoad
        @_executeTasksWithRunSequence config.done, done
      else
        done()
    , callback


  _executeTasksMatchingChangedFiles: (files, callback = ->) ->
    if not @_executingTasks
      @_executingTasks = true

      rootFileRelativePathToRootDir = path.relative @_localRootFilePath, process.cwd()
      async.eachSeries files, (filename, done) =>
        filename = filename.replace "#{@_rootPath}/", ''
        tasks = @_getTasksFromConfigMatchingTheFilename filename
        @_executeTasks tasks, done
      , =>
        if @_deferredTasks.length > 0
          @_executeDeferredTasks @_deferredTasks, callback

        else
          callback

    else
      for filename in files
        tasks = @_getTasksFromConfigMatchingTheFilename filename
        @_deferredTasks.push tasks

      gutil.log "Deferring Tasks '#{tasks.join(',')}'"
      callback()


  _executeTasks: (tasks, callback) ->
    if tasks.length > 0
      gutil.log "Executing Tasks '#{tasks.join(',')}'"
      @_executeTasksWithRunSequence tasks, callback

    else
      callback()


  _getTasksFromConfigMatchingTheFilename: (filename) ->
    tasks = []
    for config in @_options.configs
      continue if not config.patterns or not config.tasks

      patterns = _.flatten [config.patterns]
      for pattern in patterns
        if minimatch filename, pattern
          tasks.push config.tasks

    tasks


  _executeTasksWithRunSequence: (tasks, callback) ->
    gutil.log "Executing tasks '#{tasks}'"
    runSequence tasks..., ->
      gutil.log "Finished tasks '#{tasks}'"
      callback()


  _executeDeferredTasks: (callback) ->
    gutil.log "Executing deferred tasks"
    @_executeTasksWithRunSequence @_deferredTasks, ->
      gutil.log "Finished deferred tasks"
      @_deferredTasks = []
      callback()




module.exports = (options) ->
  new WatchNetwork options
