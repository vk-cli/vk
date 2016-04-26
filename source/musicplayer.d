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
       std.math;
import core.thread;
import app, utils;
import vkapi: VkMan;

struct Track {
  string artist, title, duration, playtime;
}

__gshared MusicPlayer mplayer;
__gshared VkMan api;

class MusicPlayer : Thread {
  File delegate() stdinPipe;
  Track currentTrack;
  bool
    musicState,
    playtimeUpdated,
    trackOverStateCatched = true, //for reject empty strings before playback starts
    mplayerExit,
    userSelectTrack,
    isInit;
  Track[] playlist;
  ulong lastOutputLn;
  string
    stockProgress = "=".replicate(50),
    realProgress  = "|" ~ "=".replicate(49);
  int position, trackNum, offset;

  __gshared string[] output;
  Thread listen;
  const listenWait = dur!"msecs"(500);

  this() {
    super(&runPlayer);
  }

  void exitMplayer() {
    send("quit");
  }

  void send(string cmd) {
    if (!isInit) return;
    if (canFind("loadfile", cmd)) realProgress ~= "|" ~ "=".replicate(49);
    auto stdin = stdinPipe();
    stdin.writeln(cmd);
    stdin.flush();
  }

  string durToStr(string duration) {
    auto intDuration = lround(duration.to!real);
    auto min = intDuration / 60;
    auto sec = intDuration - (60*min);
    return min.to!string ~ ":" ~ sec.to!int.tzr;
  }

  int strToDur(string duration) {
    auto temp = duration.split(":");
    return temp[0].to!int*60 + temp[1].to!int;
  }

  void setPlaytime(string answer) {
    const string start = "ANS_TIME_POSITION=";
    if (answer != "") {
      if(answer.startsWith(start)) {
        auto strtime = answer[start.length..$];
        currentTrack.playtime = durToStr(strtime);
        real
          sec = strtime.to!real,
          trackd = strToDur(currentTrack.duration).to!real,
          step =  trackd / 50;
        int newPos = floor(sec / step).to!int;
        //dbm("sec: " ~ sec.to!string ~ ", step: " ~ step.to!string ~ ", newPos: " ~ newPos.to!string ~
        //                ", mdur: " ~ trackd.to!string);
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
    }
    else {
      if(!trackOverStateCatched) trackOver();
    }
  }

  void listenStdout() {
    while (!mplayerExit) {
      //dbm("output try");
      if (output.length != lastOutputLn) {
        string answer = output[$-1];
        lastOutputLn = output.length;
        //dbm("last mp: " ~ answer);

        if (musicState) {
          setPlaytime(answer);
          send("get_time_pos");
        }
      }
      Thread.sleep(listenWait);
    }
  }

  string prepareTrackurl(string trackurl) {
    if(trackurl.startsWith("https://")) return trackurl.replace("https://", "http://");
    else return trackurl;
  }

  void trackOver() {
    if (musicState) {
      dbm("catched trackOver");
      trackOverStateCatched = true;
      if (!userSelectTrack) trackNum++;
      else userSelectTrack = false;
      auto track = api.getBufferedMusic(1, trackNum)[0];
      currentTrack.artist = track.artist;
      send("loadfile " ~ prepareTrackurl(track.url));
      currentTrack = Track(track.artist, track.title, track.duration_str);
    }
    playtimeUpdated = true;
  }

  ListElement[] getMplayerUI(int cols) {
    ListElement[] playerUI;
    playerUI ~= ListElement(" ".replicate((cols-16)/2-currentTrack.artist.utfLength/2)~currentTrack.artist);
    playerUI ~= ListElement(" ".replicate((cols-16)/2-currentTrack.title.utfLength/2)~currentTrack.title);
    playerUI ~= ListElement(center(currentTrack.playtime ~ " / " ~ currentTrack.duration, cols-16, ' '));
    playerUI ~= ListElement(center("[" ~ realProgress ~ "] ⟲ ⤮", cols-16, ' '));
    playerUI ~= ListElement("");
    return playerUI;
  }

  void runPlayer() {
    auto pipe = pipeProcess("sh", Redirect.stdin | Redirect.stdout);
    pipe.stdin.writeln("cat /dev/stdin | mplayer -slave -idle 2> /dev/null");
    pipe.stdin.flush;
    stdinPipe = &(pipe.stdin);
    isInit = true;
    currentTrack.playtime = "0:00";
    foreach (line; pipe.stdout.byLine) output ~= line.idup;
    dbm("MPLAYER EXIT");
    mplayerExit = true;
  }

  void startPlayer(VkMan vkapi) {
    api = vkapi;
    listen = new Thread(&listenStdout);
    listen.start;
    this.start;
  }

  bool sameTrack(int position) {
    auto track = api.getBufferedMusic(1, position)[0];
    return currentTrack.artist == track.artist && currentTrack.title == track.title;
  }

  void pause() {
    send("pause");
    musicState = !musicState;
  }

  void play(int position) {
    auto track = api.getBufferedMusic(1, position)[0];
    currentTrack = Track(track.artist, track.title, track.duration_str);
    send("loadfile " ~ prepareTrackurl(track.url));
    musicState = true;
  }
}
