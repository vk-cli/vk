type 
  Storage* = object
    token: string
    color: int

proc load*(): Storage = discard
proc save*() = discard