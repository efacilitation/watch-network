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
  onLoad: false
  flushDeferredTasks: true
  configs: []


class WatchNetwork extends EventEmitter

  constructor: (@_options = {}) ->
    _.defaults @_options, defaultOptions

    if @_options.gulp
      runSequence = runSequence.use @_options.gulp

    @_rootFileRegExp = new RegExp "#{@_options.rootFile}$"
    @_localRootFilePath = path.join process.cwd(), @_options.rootFile
    @_localRootPath = path.dirname @_localRootFilePath
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

      socket.on 'data', (data) =>
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
    files = @_parseFilesFromListenData buffer

    if @_waitingOnRootFileChange
      clearInterval @_waitingOnRootFileChangeIntervalId
      @_searchRootFileInChangedFilesAndWait files, =>
        files = @_stripRemoteRootPathFromFiles files
        @emit 'changed', files
        callback()

    else
      files = @_stripRemoteRootPathFromFiles files
      gutil.log "Files changed: #{files.join(', ')}"
      @_executeTasksMatchingChangedFiles files, =>
        @_executingTasks = false
        @emit 'changed', files
        callback()


  _searchRootFileInChangedFilesAndWait: (files, callback) ->
    maxRetries = 3
    retry = 0
    while (true)
      gutil.log "Got FileChange Events from Listen, searching for the RootFile in '#{files.join(',')}'"
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


  _parseFilesFromListenData: (buffer) ->
    jsonMatches = buffer.toString().match /\[[^\]]+\]/g
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
        @_executeTasksWithRunSequence config.tasks, done
      else
        done()

    , callback


  _executeTasksMatchingChangedFiles: (files, callback = ->) ->
    if not @_executingTasks
      @_executingTasks = true

      rootFileRelativePathToRootDir = path.relative @_localRootFilePath, process.cwd()
      async.eachSeries files, (filename, done) =>
        filename = filename.replace "#{@_localRootPath}/", ''
        if not @_rootFileRegExp.test filename
          tasks = @_getTasksFromConfigMatchingTheFilename filename
          if tasks.length > 0
            @_executeTasksWithRunSequence tasks, done

          else
            done()

        else
          done()

      , =>
        if @_deferredTasks.length > 0
          @_executeDeferredTasks @_deferredTasks, callback

        else
          callback()

    else
      for filename in files
        tasks = @_getTasksFromConfigMatchingTheFilename filename
        if not @_options.flushDeferredTasks
          @_deferredTasks.push tasks

      gutil.log "Deferring Tasks '#{tasks.join(',')}'"
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
    if typeof tasks is 'string'
      tasks = [tasks]

    tasks = _.flatten tasks
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
