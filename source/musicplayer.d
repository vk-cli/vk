/*
Copyright 2016 HaCk3D, substanceof

https://github.com/HaCk3Dq
https://github.com/substanceof

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import std.process, std.stdio, std.string,
       std.array, std.algorithm, std.conv,
       std.math, std.ascii,
       std.socket, std.json;
static import std.file;
import core.sys.posix.signal;
import core.thread;
import app, utils;
import vkapi: VkMan, blockType, vkAudio;

struct Track {
  string artist, title, duration, playtime, id;
  int durationSeconds;
}

__gshared MusicPlayer mplayer;
__gshared VkMan api;

class MusicPlayer {
  __gshared {
    mpv player;
    Track currentTrack;
    bool
      playtimeUpdated,
      trackOverStateCatched = true, //for reject empty strings before playback starts
      repeatMode,
      shuffleMode;
    Track[] playlist;
    string
      stockProgress = "=".replicate(50),
      realProgress  = "|" ~ "=".replicate(49);
    int position, trackNum, offset;
  }

  const updateWait = dur!"msecs"(1000);

  this() {
    player = new mpv(
      sec => setPlaytime(sec),
      {
        if(!trackOverStateCatched) trackOver();
      }
    );
  }

  void exitPlayer() {
    player.exit();
  }

  bool musicState() {
    return player.getMusicState();
  }

  void pause() {
    player.pause();
  }

  bool playerExit() {
    return player.isPlayerExit();
  }

  bool isInit() {
    return player.isPlayerInit();
  }

  void play(int position) {
    trackOverStateCatched = true;
    trackNum = position;

    vkAudio track;
    if (mplayer.shuffleMode)
      track = getShuffledMusic(1, position)[0];
    else
      track = api.getBufferedMusic(1, position)[0];

    currentTrack = Track(track.artist, track.title, track.duration_str, "", track.id.to!string, track.duration_sec);
    loadFile(track.url);
  }

  void loadFile(string url) {
    trackOverStateCatched = true;
    realProgress = "|" ~ "=".replicate(49);
    auto p = prepareTrackUrl(url);
    player.loadfile(p);
  }

  void startPlayer(VkMan vkapi) {
    currentTrack.playtime = "0:00";
    api = vkapi;
    player.start();
  }

  string durToStr(real duration) {
    auto intDuration = lround(duration);
    auto min = intDuration / 60;
    auto sec = intDuration - (60*min);
    return min.to!string ~ ":" ~ sec.to!int.tzr;
  }

  void setPlaytime(real sec) {
    real
      trackd = currentTrack.durationSeconds.to!real,
      step =  trackd / 50;
    int newPos = floor(sec / step).to!int;
    currentTrack.playtime = durToStr(sec);
    if (position != newPos) {
      position = newPos;

      if(newPos >= 50) newPos = 49;
      else if (newPos < 0) newPos = 0;

      auto newProgress = stockProgress.dup;
      newProgress[newPos] = '|';
      realProgress = newProgress.to!string;
    }
    playtimeUpdated = true;
    trackOverStateCatched = false;
  }

  string prepareTrackUrl(string trackurl) {
    if(trackurl.startsWith("https://")) return trackurl.replace("https://", "http://");
    else return trackurl;
  }

  void trackOver() {
    if (musicState) {
      dbm("catched trackOver");
      trackOverStateCatched = true;
      if (!repeatMode) trackNum++;
      int amountOfTracks = mplayer.shuffleMode ? win.savedShuffledLen : api.getServerCount(blockType.music);
      if (trackNum == amountOfTracks) {
        jumpToBeginning;
        mplayer.trackNum = win.active;
        mplayer.offset = win.scrollOffset;
      }

      vkAudio track;
      if (mplayer.shuffleMode)
        track = getShuffledMusic(1, trackNum)[0];
      else
        track = api.getBufferedMusic(1, trackNum)[0];

      loadFile(track.url);
      currentTrack = Track(track.artist, track.title, track.duration_str, "", track.id.to!string, track.duration_sec);
    }
    playtimeUpdated = true;
  }

  ListElement[] getMplayerUI(int cols) {
    ListElement[] playerUI;
    auto fcols = cols-16;
    if (currentTrack.artist.utfLength / 2 > fcols / 2) currentTrack.artist = currentTrack.artist[0..fcols-4];
    if (currentTrack.title.utfLength / 2 > fcols / 2) currentTrack.title = currentTrack.title[0..fcols-4];
    auto artistrepl = fcols / 2 - currentTrack.artist.utfLength / 2;
    auto titlerepl = fcols / 2 - currentTrack.title.utfLength / 2;

    if (fcols < 1) fcols = cols;
    if (artistrepl < 1) artistrepl = 1;
    if (titlerepl < 1) titlerepl = 1;

    playerUI ~= ListElement(" ".replicate(artistrepl)~currentTrack.artist);
    playerUI ~= ListElement(" ".replicate(titlerepl)~currentTrack.title);
    playerUI ~= ListElement(center(currentTrack.playtime ~ " / " ~ currentTrack.duration, fcols, ' '));
    playerUI ~= ListElement(center("[" ~ realProgress ~ "]", fcols, ' '));
    return playerUI;
  }

  bool sameTrack(int position) {
    vkAudio track;
    if (mplayer.shuffleMode)
      track = getShuffledMusic(1, position)[0];
    else
      track = api.getBufferedMusic(1, position)[0];
    return currentTrack.id == track.id.to!string;
  }
}

class mpv: Thread {

  enum ipcCmd {
    timeset,
    seek,
    pause,
    exit,
    load
  }

  struct ipcCmdParams {
    ipcCmd command;
    string strargument;
    real realargument;
  }

  string
    socketArgument = "--input-unix-socket=", //compatibility with older versions, changed to "--input-ipc-server=" in mpv 0.17.0
    socketPath,
    playerExec;

  const
    int
      endRequestId = 3,
      posPropertyId = 1,
      idlePropertyId = 2;

  alias posCallback = void delegate(real sec);
  alias endCallback = void delegate();

  posCallback posChanged;
  endCallback endReached;

  __gshared {
    string commandTemplate = "{ \"command\": [] }";
    Thread endChecker;
    Socket comm;
    Address commAddr;
    Pid pid = null;
    bool
      isInit,
      playerExit,
      notFirstPlay,
      musicState;
  }


  this(posCallback pos, endCallback end) {
    posChanged = pos;
    endReached = end;

    socketPath = getPlayerSocketName();
    playerExec = "mpv --idle --no-audio-display " ~ socketArgument ~ socketPath ~ " > /dev/null 2> /dev/null";

    super(&runPlayer);
  }


  private void req(string cmd) {
    //dbm("mpv <- " ~ cmd);
    if(!isInit) {
      dbm("mpv - req: noinit");
      return;
    }

    //dbm("mpv - req cmd: " ~ cmd);

    auto s_answ = comm.send(cmd ~ "\n");
    if(s_answ == Socket.ERROR) {
      dbm("mpv - req: s_answ error");
      return;
    }

  }

  private void mpvsend(ipcCmdParams c) {

    JSONValue cm = parseJSON(commandTemplate);

    switch(c.command) {
      case ipcCmd.seek:
        cm.object["command"].array ~= JSONValue("seek");
        cm.object["command"].array ~= JSONValue(c.realargument);
        cm.object["command"].array ~= JSONValue(c.strargument);
        break;
      case ipcCmd.timeset:
        cm.object["command"].array ~= JSONValue("set_property");
        cm.object["command"].array ~= JSONValue("playback-time");
        cm.object["command"].array ~= JSONValue(c.realargument);
        break;
      case ipcCmd.pause:
        cm.object["command"].array ~= JSONValue("set_property");
        cm.object["command"].array ~= JSONValue("pause");
        cm.object["command"].array ~= JSONValue(musicState);
        break;
      case ipcCmd.exit:
        cm.object["command"].array ~= JSONValue("quit");
        break;
      case ipcCmd.load:
        cm.object["command"].array ~= JSONValue("loadfile");
        cm.object["command"].array ~= JSONValue(c.strargument);
        break;
      default: assert(0);
    }

    dbm("mpv - cmd: " ~ c.command.to!string);

    req(cm.toString());
  }

  private void mpvhandle(string rc) {
    try {
      //dbm("mpv: " ~ rc);
      auto m = parseJSON(rc);
      if(m.type != JSON_TYPE.OBJECT) return;
      if(
        "request_id" in m &&
        m["request_id"].integer == endRequestId &&
        "data" in m &&
        m["data"].type == JSON_TYPE.TRUE
      ) {
        endReached();
      }
      else if("error" in m) {
        if(m["error"].str != "success") {
          dbm("mpv - error: " ~ rc);
        }
      }
      else if("event" in m) {
        auto e = m["event"].str;

        switch(e) {
          case "property-change":
            auto eid = m["id"].integer.to!int;
            if(eid == posPropertyId) posChanged(m["data"].floating.to!real);
            break;
          default: break;
        }

      }
    }
    catch(JSONException e) {
      dbm("mpv - json exception: " ~ e.msg);
    }
  }

  private void checkEnd() {
    logThread("check_end watchdog");
    while(!playerExit) {
      Thread.sleep(dur!"msecs"(500));
      if(musicState) req(checkEndCmd().toString());
    }
  }

  private JSONValue checkEndCmd() {
    JSONValue c = parseJSON("{ \"command\": [], \"request_id\": 0 }");
    c["command"].array ~= JSONValue("get_property");
    c["command"].array ~= JSONValue("idle-active");
    c["request_id"].integer = endRequestId;
    return c;
  }

  private JSONValue observePropertyCmd(int id, string prop) {
    auto c = parseJSON(commandTemplate);
    c["command"].array ~= JSONValue("observe_property");
    c["command"].array ~= JSONValue(id);
    c["command"].array ~= JSONValue(prop);
    return c;
  }

  private void setup() {
    req(observePropertyCmd(posPropertyId, "playback-time").toString());
    //req(observePropertyCmd(idlePropertyId, "end-file").toString());
    endChecker = new Thread(&checkEnd);
    endChecker.start();
  }

  void killPlayer() {
    int code = -1;
    if(pid !is null){
      code = kill(pid.processID + 1 , SIGTERM);
    }
  }

  void runPlayer() {
    logThread("runplayer");
    dbm("mpv - starting");
    auto pipe = pipeProcess("sh", Redirect.stdin);
    pipe.stdin.writeln(playerExec);
    pipe.stdin.flush;
    pid = pipe.pid;
    Thread.sleep(dur!"msecs"(500)); //wait for init
    dbm("mpv - running");

    uint spawntry;
    while(!std.file.exists(socketPath)) {
        dbm("mpv - waiting for socket spawn...");
        Thread.sleep(dur!"msecs"(400));

        ++spawntry;
        if(spawntry >= 25) {
            dbm("mpv - socket connection failed");
            return;
        }
    }
    commAddr = new UnixAddress(socketPath);
    comm = new Socket(AddressFamily.UNIX, SocketType.STREAM);
    comm.connect(commAddr);
    dbm("mpv - socket connected");

    isInit = true;
    long r_answ = -1;
    setup();

    while( r_answ != 0 ){
      char[1024] recv;
      string recv_str;
      r_answ = comm.receive(recv);
      if(r_answ != 0) {
        foreach(r; recv) {
          if(r == '\n' || r == '\x00') break;
          recv_str ~= r;
        }
        //dbm("mpv - recv: " ~ recv_str);
        mpvhandle(recv_str);
        Thread.sleep( dur!"msecs"(100) );
      }
    }

    dbm("PLAYER EXIT");
    playerExit = true;
  }

  void pause() {
    auto c = ipcCmdParams(ipcCmd.pause);
    mpvsend(c);
    musicState = !musicState;
  }

  bool getMusicState() {
    return musicState;
  }

  bool isPlayerExit() {
    return playerExit;
  }

  bool isPlayerInit() {
    return isInit;
  }

  void exit() {
    auto c = ipcCmdParams(ipcCmd.exit);
    mpvsend(c);
    Thread.sleep(dur!"msecs"(100));
    try {
        std.file.remove(socketPath);
    }
    catch(std.file.FileException e) {
        //dbm("socket not found")
    }
  }

  void loadfile(string p) {
    auto c = ipcCmdParams(ipcCmd.load, p);
    mpvsend(c);
    if(!notFirstPlay) {
      musicState = true;
      notFirstPlay = true;
    }
  }

  void setPosition(real sec) {
    auto c = ipcCmdParams(ipcCmd.timeset, "", sec);
    mpvsend(c);
  }

  void relativeSeek(real rval, bool percent) {
    auto mode = percent ? "relative-percent" : "relative";
    auto c = ipcCmdParams(ipcCmd.seek, mode, rval);
    mpvsend(c);
  }

}
