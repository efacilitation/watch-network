fs = require 'fs'

chai = require 'chai'
expect = chai.expect

sinonChai = require 'sinon-chai'
sinon = require 'sinon'
chai.use sinonChai

sandbox = sinon.sandbox.create()
mockery = require 'mockery'

mockery.enable
  useCleanCache: true
  warnOnUnregistered: false



describe 'WatchNetwork', ->

  afterEach ->
    mockery.resetCache()
    mockery.deregisterAll()
    sandbox.restore()

  asyncStub = null
  touchStub = null
  socketStub = null
  WatchNetwork = null
  netMockery = null
  beforeEach ->
    gutilStub =
      log: sandbox.stub()
    mockery.registerMock 'gulp-util', gutilStub

    touchStub =
      sync: sandbox.stub()
    mockery.registerMock 'touch', touchStub

    socketStub =
      on: sandbox.stub()
      end: sandbox.stub()
    netMockery =
      connect: sandbox.stub().returns socketStub
    netMockery.connect.yields()
    mockery.registerMock 'net', netMockery

    sandbox.stub global, 'setInterval'
    global.setInterval.yields()

    WatchNetwork = require './'


  describe '#initialize', ->
    it 'should net.connect', ->
      WatchNetwork().initialize()
      expect(netMockery.connect).to.have.been.called


    it 'should net.connect to the given host and port', ->
      WatchNetwork(
        host: 'test'
        port: '1337'
      ).initialize()

      expect(netMockery.connect).to.have.been.calledWith
        host: 'test'
        port: '1337'


  describe 'root path', ->
    it 'should touch a local .root file', ->
      netMockery.connect.yields()

      watchNetwork = WatchNetwork
        host: 'test'
        port: '1337'

      watchNetwork.initialize()

      expect(touchStub.sync).to.have.been.calledWith "#{process.cwd()}/.root"


    it 'should strip everything from the filepaths from the .root file and up', ->
      fileBuffer = toString: ->
        JSON.stringify
          added: ['/path/to/.root']

      socketStub.on.withArgs('data').yields fileBuffer
      watchNetwork = WatchNetwork()
      watchNetwork.on 'changed', (files) ->
        expect(files[0]).to.not.contain '/path/to'
        expect(files[0]).to.equal '.root'

      watchNetwork.initialize()


  describe 'file changes', ->
    watchNetwork = null
    beforeEach ->
      fileBuffer = toString: ->
        JSON.stringify
          added: ['/path/to/.root']

      socketStub.on.withArgs('data').yields fileBuffer

      watchNetwork = WatchNetwork()
      watchNetwork.initialize()


    it 'should handle multiple file changes at once after initializing', (done) ->
      fileBuffer = toString: ->
        JSON.stringify
          modified: ['/path/to/modified/file']
          added: ['/path/to/added/file']
          removed: ['/path/to/removed/file']

      watchNetwork.on 'changed', (files) ->
        expect(files).to.deep.equal [
          'modified/file'
          'added/file'
          'removed/file'
        ]
        done()

      socketStub.on.withArgs('data').yield fileBuffer


  describe 'executing tasks', (done) ->
    firstTaskCalled = false
    firstTaskCallback = null
    secondTaskCalled = false
    secondTaskCallback = null
    watchNetwork = null
    beforeEach (done) ->
      fileBuffer = toString: ->
        JSON.stringify
          added: ['/path/to/.root']

      socketStub.on.withArgs('data').yields fileBuffer

      gulp = require 'gulp'
      gulp.task 'first', (next) ->
        firstTaskCalled = true
        firstTaskCallback = next

      gulp.task 'second', (next) ->
        secondTaskCalled = true
        secondTaskCallback = next

      watchNetwork = WatchNetwork
        gulp: gulp
        flushDeferredTasks: false
        configs: [
          {
            patterns: 'first'
            tasks: 'first'
          }
          {
            patterns: 'second'
            tasks: 'second'
          }
        ]
      watchNetwork.initialize ->
        done()


    it 'should defer executing tasks if other tasks are already running', ->
      fileBuffer = toString: ->
        JSON.stringify
          modified: ['first']
      socketStub.on.withArgs('data').yield fileBuffer
      expect(firstTaskCalled).to.be.true

      fileBuffer = toString: ->
        JSON.stringify
          modified: ['second']
      socketStub.on.withArgs('data').yield fileBuffer
      expect(secondTaskCalled).to.be.false

      firstTaskCallback()

      expect(secondTaskCalled).to.be.true
