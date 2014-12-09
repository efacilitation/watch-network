'use strict'

# TODO: Specs
# TODO: Refactoring
# TODO: Cache changed files, and enqueue tasks after ~ 300 ms
#       The queue should only processed if there is no current task chain running
#       (there is currently a problem if heavy folder renaming takes place!)
# TODO: GulpJs Plugin error handling

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

    @_localRootFilePath = path.join process.cwd(), @_options.rootFile
    @_localDir = process.cwd()
    @_remoteDir = null
    @_rootFileRegExp = new RegExp "#{@_options.rootFile}$"

    # Execute config with onLoad is true
    for config in @_options.configs
      if config.onLoad
        executeTasks config.async, config.tasks

    # Destroy socket on quit
    process.on 'SIGINT', ->
      socket.destroy()
      gutil.log chalk.green "Successfully disconnected from Listen at #{@_options.host}:#{@_options.port}"
      process.exit 0


  initialize: ->
    # remove local .root file if it exists, before connecting to listen
    if fs.existsSync @_localRootFilePath
      fs.unlinkSync @_localRootFilePath

    socket = net.connect
      port: @_options.port
      host: @_options.host
      , ->
        gutil.log chalk.green "Successfully connected to Listen at #{@_options.host}:#{@_options.port}"
        touch.sync @_localRootFilePath
        gutil.log "Touched Local RootFile #{@_localRootFilePath}"

    socket.on 'data', (buffer) =>
      util = require 'util'
      json = buffer.toString()
      #json = json.match(/\{".*\}/)[0]
      json = JSON.parse json
      filenames = _.union json.modified, json.added, json.removed

      @emit 'changed', filenames

      @processFilenames filenames

      socket.end()

    socket.on 'end', =>
      # End is not working at the moment...
      gutil.log chalk.red "Connection to Listen at #{@_options.host}:#{@_options.port} lost"


  processFilenames: (filenames) ->
    for filename in filenames
      if @_rootFileRegExp.test filename
        rootFileRelativePathToRootDir = path.relative @_localRootFilePath, process.cwd()
        remoteDir = path.join filename, rootFileRelativePathToRootDir
        gutil.log chalk.green 'Successfully detected remote project directory!'
        gutil.log chalk.green "Local: #{@_localDir} - Remote: #{@_remoteDir}"
        continue

      if remoteDir
        checkTasksExecution filename.replace "#{remoteDir}/", ''
      else
        gutil.log chalk.red 'No RootFilePath set!'


  checkTasksExecution: (filename) ->
    gutil.log chalk.green "File has changed: #{filename}"
    for config in @_options.configs
      continue if not config.patterns or not config.tasks
      # Ensure array
      patterns = _.flatten [config.patterns]
      for pattern in patterns
        if minimatch filename, pattern
          executeTasks config.async, config.tasks


  executeTasks: (async, tasks) ->
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
