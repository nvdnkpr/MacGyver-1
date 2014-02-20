# Path variables
finalBuildPath = "lib/"
componentFile  = "bower.json"

child   = require "child_process"

GIT_TAG       = "git describe --tags --abbrev=0"
CHANGELOG     = "coffee ./changelog.coffee"
VERSION_REGEX = /^v\d+\.\d+\.\d+$/

getLastVersion = (callback) ->
  child.exec GIT_TAG, (error, stdout, stderr) ->
    data = if error? then "" else stdout.replace("\n", "")
    callback error, data

module.exports = (grunt) ->
  ###
  @name replace
  @description
  Replace placeholder with other values and content
  ###
  grunt.registerMultiTask "replace", "Replace placeholder with contents", ->
    options = @options
      separator: ""
      replace:   ""
      pattern:   null

    parse = (code) ->
      templateUrlRegex = options.pattern
      updatedCode      = code

      while match = templateUrlRegex.exec code
        if grunt.util._(options.replace).isFunction()
          replacement = options.replace match
        else
          replacement = options.replace

        updatedCode = updatedCode.replace match[0], replacement

      return updatedCode

    @files.forEach (file) ->
      src = file.src.filter (filepath) ->
        unless (exists = grunt.file.exists(filepath))
          grunt.log.warn "Source file '#{filepath}' not found"
        return exists
      .map (filepath) ->
        parse grunt.file.read(filepath)
      .join grunt.util.normalizelf(options.separator)

      grunt.file.write file.dest, src
      grunt.log.writeln("Replace placeholder with contents in '#{file.dest}' successfully")

  ###
  @name Marked task
  @description
  To convert markdown generated by Chalkboard to html
  ###
  grunt.registerMultiTask "marked", "Convert markdown to html", ->
    options = @options
      separator: grunt.util.linefeed

    @files.forEach (file) ->
      src = file.src.filter (filepath) ->
        unless (exists = grunt.file.exists(filepath))
          grunt.log.warn "Source file '#{filepath}' not found"
        return exists
      .map (filepath) ->
        marked = require "marked"
        marked grunt.file.read(filepath)
      .join grunt.util.normalizelf(options.separator)

      grunt.file.write file.dest, src
      grunt.log.writeln("Converted '#{file.dest}'")

  ###
  @name update:component
  @description
  Read all files in build folder and add to component.json
  ###
  grunt.registerTask "update:component", "Update bower.json", ->
    fileList = []
    grunt.file.recurse finalBuildPath, (path, root, sub, filename) ->
      fileList.push path if filename.indexOf(".DS_Store") is -1

    data         = grunt.file.readJSON componentFile, encoding: "utf8"
    data.main    = fileList
    data.name    = grunt.config.get("pkg").name
    data.version = grunt.config.get("pkg").version

    grunt.file.write componentFile, JSON.stringify(data, null, "  "), encoding: "utf8"
    grunt.log.writeln "Updated bower.json"

  ###
  @name updatebuild
  @description
  Update bower.json version of all bower repositories
  ###
  grunt.registerMultiTask "updatebuild", "Update all bower.json in build/", ->
    version = grunt.config.get("pkg").version
    options = @options
      separator: grunt.util.linefeed

    @files.forEach (file) ->
      src = file.src.filter (filepath) ->
        unless (exists = grunt.file.exists(filepath))
          grunt.log.warn "File '#{filepath}' not found"
        return exists
      .map (filepath) ->
        data         = grunt.file.readJSON filepath, encoding: "utf8"
        data.version = grunt.config.get("pkg").version
        JSON.stringify(data, null, "  ")
      .join grunt.util.normalizelf(options.separator)

      grunt.file.write file.dest, src, encoding: "utf8"
      grunt.log.writeln "Updated version in #{file.dest}"

  ###
  @name bump
  @description
  Bump package version up unless specified
  This also generate changelog with `changelog` task
  ###
  grunt.registerTask "bump", "Bump package version up and generate changelog", ->
    done = @async()

    version = grunt.option "tag"
    if version? and not VERSION_REGEX.test version
      grunt.fail.fatal "Invalid tag"

    writeAndChangelog = (newVersion) ->
      grunt.log.writeln "Updating to version #{newVersion}"

      pkg         = grunt.config.get("pkg")
      pkg.version = newVersion
      grunt.config "pkg", pkg
      grunt.file.write "package.json", JSON.stringify(pkg, null, "  "), encoding: "utf8"

      grunt.task.run "changelog"

      done()

    if version?
      writeAndChangelog version[1..]
    else
      getLastVersion (error, data) ->
        grunt.fail.fatal "Failed to read last tag" if error?

        grunt.log.writeln "Previous version #{data}"

        versionArr    = data.split "."
        versionArr[2] = +versionArr[2] + 1
        data          = versionArr.join "."

        writeAndChangelog data[1..]

  ###
  @name changelog
  @description
  Generate changelog with changelog.coffee
  ###
  grunt.registerTask "changelog", "Generate temporary changelog", ->
    done    = @async()
    version = grunt.config.get("pkg").version

    CMD = "#{CHANGELOG} v#{version} changelog.tmp.md"
    child.exec CMD, (error, stdout, stderr) ->
      grunt.fail.fatal error if error?

      grunt.log.writeln stdout
      done()

  ###
  @name tag
  @description
  Create a new commit and tag the commit with a version number
  ###
  grunt.registerTask "tag", "Tag latest commit", ->
    done    = @async()
    version = grunt.config.get("pkg").version

    CMD = [
      "git commit -am 'chore(build): Build v#{version}'"
      "git tag v#{version}"
    ].join "&&"

    child.exec CMD, (error, stdout, stderr) ->
      grunt.fail.fatal "Failed to tag" if error?
      grunt.log.writeln stdout
      done()

  ###
  @name protractor
  @description
  To run protractor. Following codes are taken from AngularJS, see:
  https://github.com/angular/angular.js/blob/master/lib/grunt/utils.js#L155
  ###
  grunt.registerMultiTask "protractor", "Run Protractor integration tests", ->
    done = @async()

    sauceUser        = grunt.option "sauceUser"
    sauceKey         = grunt.option "sauceKey"
    tunnelIdentifier = grunt.option "capabilities.tunnel-identifier"
    sauceBuild       = grunt.option "capabilities.build"
    browser          = grunt.option "browser"

    args = ["node_modules/protractor/bin/protractor", @data]
    args.push "--sauceUser=#{sauceUser}" if sauceUser
    args.push "--sauceKey=#{sauceKey}" if sauceKey
    if tunnelIdentifier
      args.push "--capabilities.tunnel-identifier=#{tunnelIdentifier}"
    if sauceBuild
      args.push "--capabilities.build='TRAVIS ##{sauceBuild}'"

    if browser
      args.push "--browser=#{browser}"
      args.push "--params.browser=#{browser}"

    if grunt.option("local")?
      args.push "--seleniumAddress=http://localhost:4444/wd/hub"

    p = child.spawn "node", args
    p.stdout.pipe process.stdout
    p.stderr.pipe process.stderr
    p.on "exit", (code) ->
      if code isnt 0
        grunt.fail.warn "Protractor test(s) failed. Exit code: #{code}"
      done()
