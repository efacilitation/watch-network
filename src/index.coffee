async       = require 'async'
net         = require 'net'
path        = require 'path'

_           = require 'lodash'
minimatch   = require 'minimatch'
runSequence = require 'run-sequence'
fs          = require 'fs'
gutil       = require 'gulp-util'
util        = require 'util'


{EventEmitter} = require 'events'

defaultOptions =
  host: 'localhost'
  port: 4000
  rootFile: '.root'
  flushDeferredTasks: true
  gulp: null
  configs: []


class WatchNetwork extends EventEmitter

  constructor: (@_options = {}) ->
    _.defaults @_options, defaultOptions

    if @_options.gulp
      runSequence = runSequence.use @_options.gulp

    @_rootFileRegExp = new RegExp "#{@_options.rootFile}$"
    @_localRootFilePath = path.join process.cwd(), @_options.rootFile
    @_tasks = {}
    @_executingTasks = false
    @_deferredTasks = []
    @_waitingOnRootFileChange = true
    @_waitingOnRootFileChangeRetries = 0
    @_waitingOnRootFileChangeMaxRetries = 3
    @_waitingOnRootFileChangeIntervalId = null
    @_initialized = false
    @lastChangeTime = null


  initialize: (callback = ->) ->
    gutil.log "Initializing"
    @on 'initialized', ->
      callback()

    @on 'changed', =>
      @lastChangeTime = new Date()

    gutil.log "Executing Tasks with onLoad flag"
    @_executeTasksOnLoad =>

      gutil.log "Connecting to Listen"
      @_socket = @_connectToSocket =>
        gutil.log "Connected to Listen at #{@_options.host}:#{@_options.port}"

      @_socket.on 'data', (data) =>
        gutil.log "Receiving Data from Listen"
        @_handleIncomingDataFromListen arguments...

      @_socket.on 'end', =>
        gutil.log "Connection to Listen lost"

      process.on 'SIGINT', =>
        @end()
        process.exit 0

    @


  task: (taskName, taskFunction) ->
    @_tasks[taskName] = taskFunction
    @


  stop: ->
    @_socket.end()
    @_socket.destroy()
    gutil.log "Disconnected from Listen"
    @removeAllListeners()
    gutil.log "Removed all Listeners"
    @


  _connectToSocket: (callback) ->
    net.connect
      port: @_options.port
      host: @_options.host
    , =>
      callback.apply arguments...
      @_touchLocalRootFileAndWait.apply arguments...


  _touchLocalRootFileAndWait: =>
    @_waitingOnRootFileChangeRetries = 0
    do fn = =>
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
        retries = "Retry #{@_waitingOnRootFileChangeRetries}/#{@_waitingOnRootFileChangeMaxRetries}: "
      gutil.log "#{retries}Waiting for incoming Listen Data.."

      @_waitingOnRootFileChangeRetries++

    @_waitingOnRootFileChangeIntervalId = setInterval fn, 500


  _touchLocalRootFile: ->
    gutil.log "Touching Local RootFile #{@_localRootFilePath}"
    fs.writeFileSync @_localRootFilePath


  _handleIncomingDataFromListen: (buffer, callback = ->) =>
    data = buffer.toString()
    gutil.log "Incoming Listen Data: #{data}"
    files = @_parseFilesFromListenData data
    gutil.log "Parsed file paths from Data", files

    if @_waitingOnRootFileChange
      clearInterval @_waitingOnRootFileChangeIntervalId
      @_searchRootFileInChangedFilesAndWait files, =>
        files = @_stripRemoteRootPathFromFiles files
        @emit 'changed', files
        callback()

    else
      files = @_stripRemoteRootPathFromFiles files
      gutil.log "Files changed: #{files}"
      @_executeTasksMatchingChangedFiles files, =>
        @emit 'changed', files
        callback()


  _searchRootFileInChangedFilesAndWait: (files, callback) ->
    maxRetries = 3
    retry = 0
    while (true)
      gutil.log "Got FileChange Events from Listen, searching for the RootFile in '#{files}'"
      if @_searchRootFileInChangedFiles files
        gutil.log "Successfully detected RootFile and set RemoteRootPath to '#{@_remoteRoothPath}'!"
        @_waitingOnRootFileChange = false
        @_removeLocalRootFile()
        @emit 'initialized', files
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
    for filename in files
      if @_rootFileRegExp.test filename
        @_remoteRoothFilePath = filename
        @_remoteRoothPath = path.dirname filename
        return true

    return false


  _removeLocalRootFile: ->
    if fs.existsSync @_localRootFilePath
      fs.unlinkSync @_localRootFilePath


  _parseFilesFromListenData: (data) ->
    jsonMatches = data.match /\[[^\[\]]+\]/g
    files = []
    for jsonMatch in jsonMatches
      json = JSON.parse jsonMatch
      filename = "#{json[2]}/#{json[3]}"
      if (files.indexOf filename) is -1
        files.push filename

    files


  _stripRemoteRootPathFromFiles: (files) ->
    remoteDirRegExp = new RegExp "#{@_remoteRoothPath}/?"
    files = files.map (file) =>
      file.replace remoteDirRegExp, ''


  _executeTasksOnLoad: (callback = ->) ->
    async.eachSeries @_options.configs, (config, done) =>
      if config.onLoad
        @_executeTasks config.tasks, done
      else
        done()

    , callback


  _executeTasksMatchingChangedFiles: (files, callback = ->) ->
    if @_executingTasks
      for filename in files
        tasks = @_getTasksFromConfigMatchingTheFilename filename
        @_deferredTasks = @_deferredTasks.concat tasks

      gutil.log "Deferred Tasks '#{@_deferredTasks}'"
      return callback()

    @_executingTasks = true
    async.eachSeries files, (filename, done) =>
      if @_rootFileRegExp.test filename
        return done()

      tasks = @_getTasksFromConfigMatchingTheFilename filename
      if tasks.length <= 0
        return done()

      @_executeTasks tasks, done

    , =>
      @_executeDeferredTasks =>
        @_executingTasks = false
        callback()


  _getTasksFromConfigMatchingTheFilename: (filename) ->
    tasks = []
    for config in @_options.configs
      continue if not config.patterns or not config.tasks

      if typeof config.patterns is 'string'
        config.patterns = [config.patterns]

      for pattern in config.patterns
        if minimatch filename, pattern
          gutil.log "Pattern '#{pattern}' matched. Queueing tasks '#{config.tasks}'"
          tasks = tasks.concat config.tasks

    tasks


  _executeTasks: (tasks, callback) ->
    if typeof tasks is 'string'
      tasks = [tasks]

    gutil.log "Executing tasks '#{tasks}'"
    async.eachSeries tasks, (task, done) =>
      if not @_tasks[task] or typeof @_tasks[task] isnt 'function'
        return done()

      @_tasks[task] done
    , =>
      gutil.log "Finished Executing tasks"
      if @_options.gulp
        @_executeGulpTasksWithRunSequence tasks, callback
      else
        callback()


  _executeDeferredTasks: (callback) ->
    if @_deferredTasks.length <= 0
      return callback()

    if @_options.flushDeferredTasks
      gutil.log "Flushing deferred tasks '#{@_deferredTasks}'"
      return callback()

    gutil.log "Executing deferred tasks"
    @_executeTasks @_deferredTasks, ->
      gutil.log "Finished deferred tasks"
      @_deferredTasks = []
      callback()


  _executeGulpTasksWithRunSequence: (tasks, callback) ->
    gutil.log "Executing gulp-tasks with run-sequence '#{tasks}'"
    runSequence tasks..., ->
      gutil.log "Finished Executing gulp-tasks with run-sequence '#{tasks}'"
      callback()


module.exports = (options) ->
  new WatchNetwork options
