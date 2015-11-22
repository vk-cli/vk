import os, parsecfg, strutils, streams

let
  config = getHomeDir() & ".vkrc"

proc save*(token: string, color: int) =
  open(config, fmWrite).close()
  var f = open(config, fmWrite)
  defer: close(f)
  f.writeLine("token = " & token)
  f.writeLine("color = " & $color)

proc load*() = 
  if fileExists(config):
    var
      f = newFileStream(config, fmRead)
      p: CfgParser
    open(p, f, config)
    while true:
      var e = next(p)
      case e.kind
      of cfgEof: break
      of cfgSectionStart: discard
      of cfgKeyValuePair: echo(e.key & " = " & e.value)
      of cfgOption: discard
      of cfgError: discard
    close(p)