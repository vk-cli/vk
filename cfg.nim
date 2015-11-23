import os, parsecfg, strutils, streams, tables

let
  ConfigPath = getHomeDir() & ".vkrc"

proc save*(config: Table) =
  open(ConfigPath, fmWrite).close()
  var f = open(ConfigPath, fmWrite)
  defer: close(f)
  for key, value in config.pairs:
    f.writeLine(key & " = " & value)

proc load*(): Table[string, string] = 
  var box = initTable[string, string]()
  if fileExists(ConfigPath):
    var
      f = newFileStream(ConfigPath, fmRead)
      p: CfgParser
    open(p, f, ConfigPath)
    while true:
      var e = next(p)
      case e.kind
      of cfgKeyValuePair: box[e.key] = e.value
      of cfgSectionStart: discard
      of cfgOption: discard
      of cfgError: discard
      of cfgEof: break
    close(p)
  return box