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
       std.math, std.file, std.ascii,
       std.socket, std.json;
import core.thread;
import app, utils;
import vkapi: VkMan;

struct Track {
  string artist, title, duration, playtime, id;
  int durationSeconds;
}

__gshared MusicPlayer mplayer;
__gshared VkMan api;

class MusicPlayer : Thread {
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
    player = new mpv();
    super(&playerControl);
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
    auto track = api.getBufferedMusic(1, position)[0];
    currentTrack = Track(track.artist, track.title, track.duration_str, "", track.id.to!string, track.duration_sec);
    loadFile(track.url);
  }

  void playerControl() {
    while(!playerExit) {
      Thread.sleep(updateWait);
      if(isInit) {
        bool t_end;
        auto t_time = player.getPlaytime(t_end);
        setPlaytime(t_time, t_end);
      }
    }
  }

  void loadFile(string url) {
    realProgress = "|" ~ "=".replicate(49);
    auto p = prepareTrackUrl(url);
    player.loadfile(p);
  }

  void startPlayer(VkMan vkapi) {
    currentTrack.playtime = "0:00";
    api = vkapi;
    player.start();
    this.start();
  }

  string durToStr(real duration) {
    auto intDuration = lround(duration);
    auto min = intDuration / 60;
    auto sec = intDuration - (60*min);
    return min.to!string ~ ":" ~ sec.to!int.tzr;
  }

  void setPlaytime(real sec, bool end) {
    if (!end) {
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
    else {
      if(!trackOverStateCatched) trackOver();
    }
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
      auto track = api.getBufferedMusic(1, trackNum)[0];
      loadFile(track.url);
      currentTrack = Track(track.artist, track.title, track.duration_str, "", track.id.to!string, track.duration_sec);
    }
    playtimeUpdated = true;
  }

  ListElement[] getMplayerUI(int cols) {
    ListElement[] playerUI;
    auto fcols = cols-16;
    auto artistrepl = fcols/2-currentTrack.artist.utfLength/2;
    auto titlerepl = fcols/2-currentTrack.title.utfLength/2;

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
    auto track = api.getBufferedMusic(1, position)[0];
    return currentTrack.id == track.id.to!string;
  }
}

class mpv: Thread {

  enum ipcCmd {
    playbackTime,
    pause,
    exit,
    load
  }

  struct ipcResult {
    bool success;
    bool nodata;
    string error;

    real realval;
    int intval;
    bool boolval;
  }

  struct ipcCmdParams {
    ipcCmd command;
    string argument;
  }

  const
    socketPath = "/tmp/vkmpv",
    playerExec = "mpv --idle --no-audio-display --input-ipc-server=" ~ socketPath ~ " > /dev/null 2> /dev/null";

  string[] output;
  Socket comm;
  Address commAddr;
  bool
    isInit,
    playerExit,
    musicState;


  this() {
    super(&runPlayer);
  }


  private string req(string cmd) {
    if(!isInit) {
      dbm("mpv - req: noinit");
      return "";
    }

    dbm("mpv - req cmd: " ~ cmd);

    auto s_answ = comm.send(cmd ~ "\n");
    if(s_answ == Socket.ERROR) {
      dbm("mpv - req: s_answ error");
      return "";
    }

    string str_recv;

    for(int i; i < 1; i++) {
      byte[] recv;
      auto r_answ = comm.receive(recv);
      dbm("mpv - req: r_answ " ~ r_answ.to!string);
      if(r_answ == Socket.ERROR) {
        return "";
      }
      str_recv = recv.to!string;
      dbm("mpv - req recv: " ~ str_recv);
    }
    return str_recv;
  }

  private ipcResult mpvsend(ipcCmdParams c) {

    JSONValue cm = parseJSON("{ \"command\": [] }");

    switch(c.command) {
      case ipcCmd.playbackTime:
        cm.object["command"].array ~= JSONValue("get_property");
        cm.object["command"].array ~= JSONValue("playback-time");
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
        cm.object["command"].array ~= JSONValue(c.argument);
        break;
      default: assert(0);
    }

    dbm("mpv - cmd: " ~ c.command.to!string);

    auto answ = req(cm.toString());
    auto rt = ipcResult();
    JSONValue recv;

    if(answ == "") {
        dbm("mpv - empty answer");
        return rt;
    }
    try {
      recv = parseJSON(answ);

      if("error" in recv) {
        auto err = recv["error"].str;
        rt.error = err;
        if(err == "success") {
          rt.success = true;
        }
        else {
          dbm("mpv - error: " ~  err);
        }
      }

      if(rt.success) {
        if("data" in recv) {
          auto d = recv["data"];
          switch(d.type) {
            case JSON_TYPE.INTEGER:
              rt.intval = d.integer.to!int;
              break;
            case JSON_TYPE.FLOAT:
              rt.realval = d.floating.to!real;
              break;
            case JSON_TYPE.TRUE:
              rt.boolval = true;
              break;
            case JSON_TYPE.FALSE:
              rt.boolval = false;
              break;
            default:
              dbm("mpv - unknown data");
              rt.nodata = true;
              break;
          }
        }
        else {
          dbm("mpv - no data");
          rt.nodata = true;
        }
      }

    }
    catch(JSONException e) {
      dbm("mpv - json exception " ~ e.msg);
    }

    return rt;

  }

  void runPlayer() {
    dbm("mpv - starting");
    auto pipe = pipeProcess("sh", Redirect.stdin);
    pipe.stdin.writeln(playerExec);
    pipe.stdin.flush;
    Thread.sleep(dur!"msecs"(500)); //wait for init
    dbm("mpv - running");

    assert(exists(socketPath));
    commAddr = new UnixAddress(socketPath);
    comm = new Socket(AddressFamily.UNIX, SocketType.STREAM);
    comm.connect(commAddr);
    dbm("mpv - socket connected");

    isInit = true;
    /*foreach (line; pipe.stdout.byLine) {
      output ~= line.idup;
      dbm("mpv out: " ~ line.to!string);
    }*/
    while (true) Thread.sleep( dur!"msecs"(1000));
    dbm("PLAYER EXIT");
    playerExit = true;
  }

  void pause() {
    auto c = ipcCmdParams(ipcCmd.pause);
    auto a = mpvsend(c);
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
    auto a = mpvsend(c);
  }

  void loadfile(string p) {
    auto c = ipcCmdParams(ipcCmd.load, p);
    auto a = mpvsend(c);
    musicState = true;
  }

  real getPlaytime(out bool trackEnd) {
    trackEnd = false;
    return 0;
  }

}
