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
  fileSyncBufferTime: 50
  flushDeferredTasks: true
  gulp: null
  configs: []
  logLevel: 'info'


class WatchNetwork extends EventEmitter

  constructor: (@_options = {}) ->
    _.defaults @_options, defaultOptions

    if @_options.gulp
      runSequence = runSequence.use @_options.gulp

    @_rootFileRegExp = new RegExp "#{@_options.rootFile}$"
    @_localRootFilePath = path.join process.cwd(), @_options.rootFile
    @_tasks = {}
    @_executingTasks = false
    @_deferredTaskMatches = []
    @_waitingOnRootFileChange = true
    @_waitingOnRootFileChangeRetries = 0
    @_waitingOnRootFileChangeMaxRetries = 3
    @_waitingOnRootFileChangeIntervalId = null
    @_queuingFileChanges = false
    @_queuedChangedFiles = []
    @_initialized = false
    @lastChangeTime = null
    @log = new Logger
    @log.setLogLevel @_options.logLevel


  initialize: (callback = ->) ->
    @log.info "Initializing"

    @on 'initialized', =>
      @log.info "Initialized"
      callback()

    @on 'changed', =>
      @lastChangeTime = new Date()

    @_executeTasksOnLoad =>

      @log.info "Connecting to Listen"
      @_socket = @_connectToSocket =>
        @log.info "Connected to Listen at #{@_options.host}:#{@_options.port}"

      @_socket.on 'data', (buffer) =>
        @_handleIncomingDataFromListen buffer.toString()

      @_socket.on 'end', =>
        @log.info "Connection to Listen lost"

      process.on 'SIGINT', =>
        @stop()
        process.exit 0

    @


  task: (taskName, taskFunction) ->
    @_tasks[taskName] = taskFunction
    @


  stop: ->
    @_socket.end()
    @_socket.destroy()
    @log.info "Disconnected from Listen"
    @removeAllListeners()
    @log.debug "Removed all Listeners"
    @


  _connectToSocket: (callback) ->
    net.connect
      port: @_options.port
      host: @_options.host
    , =>
      callback.apply arguments...
      @_touchLocalRootFileAndWait.apply arguments...


  _touchLocalRootFileAndWait: =>
    if @_waitingOnRootFileChangeRetries > @_waitingOnRootFileChangeMaxRetries
      err = "No change event after touching the RootFile, aborting..
            (max retries reached: #{@_waitingOnRootFileChangeMaxRetries})"
      @log.debug err
      throw new Error err

    @_touchLocalRootFile()

    retries = ""
    if @_waitingOnRootFileChangeRetries > 0
      retries = " Retry #{@_waitingOnRootFileChangeRetries}/#{@_waitingOnRootFileChangeMaxRetries}: "

    @log.debug "Waiting for incoming Listen Data..#{retries}"

    @_waitingOnRootFileChangeRetries++

    setTimeout =>
      if not @_waitingOnRootFileChange
        return

      @_waitingOnRootFileChangeRetries++
      @_touchLocalRootFile()
    , 100


  _touchLocalRootFile: ->
    @log.debug "Touching Local RootFile #{@_localRootFilePath}"
    fs.writeFileSync @_localRootFilePath


  _handleIncomingDataFromListen: (data, callback = ->) =>
    @log.debug "Incoming Listen Data: #{data}"

    files = @_parseFilesFromListenData data

    if @_waitingOnRootFileChange
      @_searchRootFileInChangedFilesAndWait files, =>
        @_waitingOnRootFileChange = false
        @_waitingOnRootFileChangeRetries = 0
        files = @_stripRemoteRootPathFromFiles files
        callback()
      return

    files = @_stripRemoteRootPathFromFiles files

    if @_queuingFileChanges
      @_queuedChangedFiles = @_queuedChangedFiles.concat files
      return

    @log.debug "Waiting for #{@_options.fileSyncBufferTime}ms on file changes for sync and buffering purposes"
    @_queuedChangedFiles = @_queuedChangedFiles.concat files
    @_queuingFileChanges = setTimeout =>
      files = @_arrayUnique @_queuedChangedFiles
      @log.debug "Handling queued File Changes", files
      @_queuingFileChanges = false

      @log.info "Changed Files: #{files.join ', '}"
      @_executeTasksMatchingChangedFiles files, =>
        @emit 'changed', files
        callback()

      @_queuedChangedFiles = []

    , @_options.fileSyncBufferTime



  _searchRootFileInChangedFilesAndWait: (files, callback) ->
    @log.debug "Got FileChange Events from Listen, searching for the RootFile in '#{files}'"
    if @_searchRootFileInChangedFiles files
      @log.debug "Successfully detected RootFile and set RemoteRootPath to '#{@_remoteRoothPath}'!"
      @_removeLocalRootFile()
      @_initialized = true
      callback()
      @emit 'initialized', files

    else
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
    @log.debug "Executing Tasks with onLoad flag"
    async.eachSeries @_options.configs, (config, done) =>
      if config.onLoad
        @_executeTasks config.tasks, '', done
      else
        done()

    , callback


  _executeTasksMatchingChangedFiles: (files, callback = ->) ->
    if @_executingTasks
      tasks = []
      for filename in files
        matches = @_matchFilenameAgainstConfigsPatterns filename
        @_deferredTaskMatches = @_deferredTaskMatches.concat matches
        for match in matches
          tasks = tasks.concat match.tasks

      if tasks.length > 0
        @log.info "Deferred Tasks '#{tasks}'"
      return callback()

    @_executingTasks = true
    async.eachSeries files, (filename, done) =>
      if @_rootFileRegExp.test filename
        return done()

      matches = @_matchFilenameAgainstConfigsPatterns filename
      if matches.length <= 0
        return done()

      @_executeMatchedTasks matches, done

    , =>
      @_executeDeferredTasks =>
        @_executingTasks = false
        callback()


  _matchFilenameAgainstConfigsPatterns: (filename) ->
    matches = []
    for config in @_options.configs
      continue if not config.patterns or not config.tasks

      if typeof config.patterns is 'string'
        config.patterns = [config.patterns]

      matched = false
      for pattern in config.patterns
        if minimatch filename, pattern
          matched = true

      continue if not matched

      @log.debug "Pattern '#{pattern}' matched. Queueing tasks '#{config.tasks}'"
      matches.push
        filename: filename
        tasks: config.tasks

    matches


  _executeMatchedTasks: (matches, callback) ->
    async.eachSeries matches, (match, done) =>
      @_executeTasks match.tasks, match.filename, done
    , ->
      callback()


  _executeTasks: (tasks, changedFile, callback) ->
    if typeof tasks is 'string'
      tasks = [tasks]

    if tasks.length is 0
      return callback()

    async.eachSeries tasks, (task, done) =>
      if not @_tasks[task] or typeof @_tasks[task] isnt 'function'
        return done()

      @log.info "Executing task '#{task}'"
      @_executeTask task, changedFile, =>
        @log.info "Finished Executing task '#{task}'"
        done()

    , =>
      if @_options.gulp
        @_executeGulpTasksWithRunSequence tasks, callback
      else
        callback()


  _executeTask: (task, changedFile, callback) ->
    taskFunction   = @_tasks[task]
    taskArgsLength = taskFunction.length
    if taskArgsLength is 0
      @_tasks[task]()
      callback()
    else if taskArgsLength is 2
      @_tasks[task] changedFile, ->
        callback()


  _executeDeferredTasks: (callback) ->
    if @_deferredTaskMatches.length <= 0
      return callback()

    if @_options.flushDeferredTasks
      @log.debug "Flushing deferred tasks '#{@_deferredTaskMatches}'"
      return callback()

    @log.info "Executing deferred tasks"
    @_executeMatchedTasks @_deferredTaskMatches, '', =>
      @log.info "Finished deferred tasks"
      @_deferredTaskMatches = []
      callback()


  _executeGulpTasksWithRunSequence: (tasks, callback) ->
    @log.info "Executing gulp-tasks with run-sequence '#{tasks}'"
    tasks = tasks.filter (task) =>
      @_options.gulp.tasks[task]

    if tasks.length is 0
      return callback()

    runSequence tasks..., =>
      @log.info "Finished Executing gulp-tasks with run-sequence '#{tasks}'"
      callback()


  _arrayUnique: (a) ->
    a.reduce (p, c) ->
      p.push c if p.indexOf(c) < 0
      return p
    , []


class Logger
  _logLevel: 1
  setLogLevel: (logLevel) ->
    @_logLevel = switch logLevel
      when 'debug' then 0
      when 'warn' then 1
      when 'info' then 2
      when 'error' then 3

  debug: ->
    return if @_logLevel > 0
    gutil.log arguments...

  warn: ->
    return if @_logLevel > 1
    gutil.log arguments...

  info: ->
    return if @_logLevel > 2
    gutil.log arguments...

  error: ->
    return if @_logLevel > 3
    gutil.log arguments...



module.exports = (options) ->
  new WatchNetwork options
