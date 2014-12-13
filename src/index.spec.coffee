fs = require 'fs'


describe 'WatchNetwork', ->
  asyncStub = null
  fsStub = null
  socketStub = null
  WatchNetwork = null
  netMockery = null
  beforeEach ->
    gutilStub =
      log: sandbox.stub()
    mockery.registerMock 'gulp-util', gutilStub

    fsStub =
      existsSync: sandbox.stub().returns true
      unlinkSync: sandbox.stub()
      writeFileSync: sandbox.stub()
    mockery.registerMock 'fs', fsStub

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


    it 'should execute onLoad tasks', ->
      fancyCalled = false
      gulp = require 'gulp'
      gulp.task 'fancy', ->
        fancyCalled = true

      watchNetwork = WatchNetwork
        gulp: gulp
        configs: [
          {
            tasks: 'fancy'
            onLoad: true
          }
        ]

      watchNetwork.initialize ->
        expect(fancyCalled).to.be.true


  describe 'root path', ->
    it 'should touch a local .root file', ->
      netMockery.connect.yields()

      watchNetwork = WatchNetwork().initialize()

      expect(fsStub.writeFileSync).to.have.been.calledWith "#{process.cwd()}/.root"


    it 'should strip everything from the filepaths from the .root file and up', (done) ->
      fileBuffer = toString: ->
        JSON.stringify [null, null, "/path/to/tmp", '.root']

      socketStub.on.withArgs('data').yields fileBuffer

      watchNetwork = WatchNetwork
        rootFile: './tmp/.root'
      watchNetwork.on 'changed', (files) ->
        expect(files[0]).to.not.contain 'tmp'
        expect(files[0]).to.equal '.root'
        done()

      watchNetwork.initialize()


  describe 'file changes', ->
    watchNetwork = null
    beforeEach ->
      fileBuffer = toString: ->
        JSON.stringify [null, null, '/path/to', '.root']

      socketStub.on.withArgs('data').yields fileBuffer

      watchNetwork = WatchNetwork()
      watchNetwork.initialize()


    it 'should handle multiple file changes at once after initializing', (done) ->
      watchNetwork.on 'changed', (files) ->
        expect(files).to.deep.equal [
          'modified/file'
          'added/file'
          'removed/file'
        ]
        done()

      fileBuffer = toString: ->
        str  = JSON.stringify [null, null, '/path/to/modified', 'file']
        str += JSON.stringify [null, null, '/path/to/added', 'file']
        str += JSON.stringify [null, null, '/path/to/removed', 'file']
        str
      socketStub.on.withArgs('data').yield fileBuffer


  describe 'executing deferred tasks', (done) ->
    firstTaskCalled = false
    firstTaskCallback = null
    secondTaskCalled = false
    secondTaskCallback = null
    watchNetwork = null
    beforeEach (done) ->
      fileBuffer = toString: ->
        JSON.stringify [null, null, '/path/to', '.root']

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
        JSON.stringify [null, null, '/path/to', 'first']
      socketStub.on.withArgs('data').yield fileBuffer
      expect(firstTaskCalled).to.be.true

      fileBuffer = toString: ->
        JSON.stringify [null, null, '/path/to', 'second']
      socketStub.on.withArgs('data').yield fileBuffer
      expect(secondTaskCalled).to.be.false

      firstTaskCallback()

      expect(secondTaskCalled).to.be.true
