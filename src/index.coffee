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
    @_remoteDir = null


  initialize: ->
    if fs.existsSync @_localRootFilePath
      fs.unlinkSync @_localRootFilePath

    socket = net.connect
      port: @_options.port
      host: @_options.host
      , =>
        gutil.log chalk.green "Successfully connected to Listen at #{@_options.host}:#{@_options.port}"
        gutil.log "Touching Local RootFile #{@_localRootFilePath}"
        touch.sync @_localRootFilePath

    socket.on 'data', (buffer) =>
      json  = @_parseJsonFromListenPayload buffer
      files = @_convertListenJsonToArray json
      @_findRoot files
      files = @_stripRootPathFromFiles files
      @emit 'changed', files
      @_handleFileChanges files
      socket.end()

    socket.on 'end', =>
      # End is not working at the moment...
      gutil.log chalk.red "Connection to Listen at #{@_options.host}:#{@_options.port} lost"

    # Execute config with onLoad is true
    for config in @_options.configs
      if config.onLoad
        @_executeTasks config.async, config.tasks

    # Destroy socket on quit
    process.on 'SIGINT', =>
      socket.destroy()
      gutil.log chalk.green "Successfully disconnected from Listen at #{@_options.host}:#{@_options.port}"
      process.exit 0


  _stripRootPathFromFiles: (files) ->
    remoteDirRegExp = new RegExp "#{@_remoteDir}/?"
    files = files.map (file) =>
      file.replace remoteDirRegExp, ''


  _parseJsonFromListenPayload: (buffer) ->
    json = buffer.toString()
    json = json.match(/\{[\s\S]*\}/)[0]
    json = JSON.parse json


  _convertListenJsonToArray: (json) ->
    _.union json.modified, json.added, json.removed


  _findRoot: (files) ->
    if @_remoteDir
      return

    rootFileRegExp = new RegExp "#{@_options.rootFile}$"
    gutil.log "Scanning for FileChange Event from Listen containing the RootFile #{@_localRootFilePath}"

    rootFileRelativePathToRootDir = path.relative @_localRootFilePath, process.cwd()
    for filename in files
      if not rootFileRegExp.test filename
        continue

      @_remoteDir = path.join filename, rootFileRelativePathToRootDir
      gutil.log chalk.green 'Successfully detected remote project directory!'
      gutil.log chalk.green "Local: #{@_localDir} - Remote: #{@_remoteDir}"
      break

    if not @_remoteDir
      gutil.log "Couldnt find the RootFile in the Changed Files, aborting.."
      process.exit 1


  _handleFileChanges: (files) ->
    rootFileRelativePathToRootDir = path.relative @_localRootFilePath, process.cwd()
    for filename in files
      @_checkTasksExecution filename.replace "#{@_remoteDir}/", ''


  _checkTasksExecution: (filename) ->
    gutil.log chalk.green "File has changed: #{filename}"
    for config in @_options.configs
      continue if not config.patterns or not config.tasks
      # Ensure array
      patterns = _.flatten [config.patterns]
      for pattern in patterns
        if minimatch filename, pattern
          @_executeTasks config.async, config.tasks


  _executeTasks: (async, tasks) ->
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
