import std.process, std.stdio, std.string,
       std.array, std.algorithm, std.conv;
import core.thread;
import app, utils;
import vkapi: VKapi;

struct Track {
  string artist, title, duration, playtime;
}

__gshared MusicPlayer mplayer;
__gshared VKapi api;

class MusicPlayer : Thread {
  File delegate() stdinPipe;
  Track currentTrack;
  bool
    musicState,
    playtimeUpdated,
    mplayerExit,
    isInit;
  Track[] playlist;
  ulong lastOutputLn;
  string
    stockProgress = "=".replicate(50),
    realProgress  = "|" ~ "=".replicate(49);
  int position, trackNum;

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
    if (canFind("loadfile", cmd)) realProgress = realProgress = "|" ~ "=".replicate(49);
    auto stdin = stdinPipe();
    stdin.writeln(cmd);
    stdin.flush();
  }

  string durToStr(string duration) {
    int intDuration = duration.to!int;
    int min = intDuration / 60;
    int sec = intDuration - (60*min);
    return min.to!string ~ ":" ~ sec.tzr;
  }

  int strToDur(string duration) {
    auto temp = duration.split(":");
    return temp[0].to!int*60 + temp[1].to!int;
  }

  void setPlaytime() {
    send("get_time_pos");
    string answer = output[$-1];
    if (answer != "" && answer.canFind("ANS")) {
      currentTrack.playtime = durToStr(answer[18..$-2]);
      int
        sec = answer[18..$-2].to!int,
        step = strToDur(currentTrack.duration) / 50,
        newPos = sec / step;
      if (position != newPos) {
        position = newPos;
        auto newProgress = stockProgress.dup; 
        newProgress[newPos] = '|';
        realProgress = newProgress.to!string;
      }
    }
    playtimeUpdated = true;
  }

  void isTrackOver() {
    send("get_percent_pos");
    if (musicState && output[$-1] == "") {
      currentTrack.artist = "load";
      auto track = api.getBufferedMusic(1, ++trackNum)[0];
      currentTrack.artist = "done";
      currentTrack.artist = track.artist;
      //send("loadfile " ~ track.url);
      //currentTrack = Track(track.artist, track.title, track.duration_str);
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
    mplayerExit = true;
  }

  void listenStdout() {
    while (!mplayerExit) {
      if (output.length != lastOutputLn) {
        lastOutputLn = output.length;
        if (musicState) {
          setPlaytime;
          //isTrackOver;
        }
      }
      Thread.sleep(listenWait);
    }
  }

  void startPlayer(VKapi vkapi) {
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
    trackNum = position;
    auto track = api.getBufferedMusic(1, position)[0];
    send("loadfile " ~ track.url);
    musicState = true;
    currentTrack = Track(track.artist, track.title, track.duration_str);
  }
}
