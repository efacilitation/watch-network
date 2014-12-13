[![Build Status](https://travis-ci.org/efacilitation/gulp-watch-network.svg?branch=master)](https://travis-ci.org/efacilitation/gulp-watch-network)

## Information

<table>
<tr>
<td>Package</td><td>gulp-watch-network</td>
</tr>
<tr>
<td>Description</td>
<td>Watch File Events received over the Network using net.connect</td>
</tr>
</table>

Based on the Listen Feature "[Forwarding file events over TCP](https://github.com/guard/listen#forwarding-file-events-over-tcp)", this plugin will connect to a Listen broadcaster as a receiver and watch for File Events. Upon receiving a File Event it will execute `tasks` based on `patterns`. This can be useful for virtualized development environments when file events are unavailable, as is the case with [Vagrant](https://github.com/mitchellh/vagrant) / [VirtualBox](https://www.virtualbox.org).

> Listen >2.8 required

## Usage

```javascript
gulp = require('gulp');
gulp.task('something:important', function() {
  // ..
});

WatchNetwork = require("gulp-watch-network");

watch = WatchNetWork({
  gulp: gulp,
  host: '127.0.0.1',
  configs: [
    {
      tasks: 'something:important'
      onLoad: true
    }, {
      patterns: 'lib/*.coffee'
      tasks: ['something:important', 'another:thing']
    }
  ]
});

watch.on('changed', function(files) {
  // .. files changed..
});

watch.on('initialized', function(files) {
  // .. watcher finished initializing..
});

watch.initialize();

```


## License
Licensed under the MIT license.
