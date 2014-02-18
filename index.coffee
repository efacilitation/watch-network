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

defaultOptions =
  host: 'localhost'
  port: 4000
  rootFile: '.root'
  onLoad: false

module.exports = (options = {}) ->

  _.defaults options, defaultOptions
  if not _.isArray options.configs
    console.log chalk.red 'PluginError: No configs defined!'
    return
  rootFileRegExp = new RegExp "#{options.rootFile}$"

  localRootFilePath = path.join process.cwd(), options.rootFile
  localDir = process.cwd()
  remoteDir = null

  processFilenames = (filenames) ->
    for filename in filenames
      if rootFileRegExp.test filename
        rootFileRelativePathToRootDir = path.relative localRootFilePath, process.cwd()
        remoteDir = path.join filename, rootFileRelativePathToRootDir
        console.log chalk.green 'Successfully detected remote project directory!'
        console.log chalk.green "Local: #{localDir} - Remote: #{remoteDir}"
        continue

      if remoteDir
        checkTasksExecution filename.replace "#{remoteDir}/", ''
      else
        console.log chalk.red 'No RootFilePath set!'

  checkTasksExecution = (filename) ->
    console.log chalk.green "File has changed: #{filename}"
    for config in options.configs
      continue if not config.patterns or not config.tasks
      # Ensure array
      patterns = _.flatten [config.patterns]
      for pattern in patterns
        if minimatch filename, pattern
          executeTasks config.async, config.tasks

  executeTasks = (async, tasks) ->
    console.log chalk.magenta "Execute GulpJs tasks \"#{tasks}\" - [async: #{!!async}]"
    finshedTasks = ->
      console.log chalk.magenta "Finished GulpJs tasks \"#{tasks}\" - [async: #{!!async}]"

    # Ensure array
    tasks = _.flatten [tasks]

    if async
      runSequence tasks, finshedTasks
    else
      clonedTasks = _.clone tasks
      clonedTasks.push finshedTasks
      runSequence.apply runSequence, clonedTasks

  socket = null
  initSocket = ->

    socket = net.connect
      port: options.port
      host: options.host
      , ->
        console.log chalk.green "Successfully connected to Listen at #{options.host}:#{options.port}"
        touch.sync localRootFilePath

    socket.on 'data', (buffer) ->
      util = require 'util'
      json = buffer.toString()
      json = json.match(/{.*}/)[0]
      json = JSON.parse json
      filenames = _.union json.modified, json.added, json.removed

      processFilenames filenames

      socket.end()

    socket.on 'end', ->
      # End is not working at the moment...
      console.log chalk.red 'Connection to Listen at #{options.host}:#{options.port} lost'

  # Execute config with onLoad is true
  for config in options.configs
    if config.onLoad
      executeTasks config.async, config.tasks

  # Init socket
  initSocket()

  # Destroy socket on quit
  process.on 'SIGINT', ->
    socket.destroy()
    console.log chalk.green "Successfully disconnected from Listen at #{options.host}:#{options.port}"
    process.exit 0