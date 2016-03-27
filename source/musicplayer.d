import std.process, std.stdio, std.string, std.array, std.algorithm, std.conv, core.thread;
import app, utils;

struct Track {
  string artist, title, duration, playtime;
}

__gshared MusicPlayer mplayer;

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
    stockProgress = "========================================",
    realProgress  = "|=======================================";
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
    if (canFind("loadfile", cmd)) mplayer.realProgress  = "|=======================================";
    auto stdin = mplayer.stdinPipe();
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

  void setPlaytime(string answer) {
    if (answer != "") {
      mplayer.currentTrack.playtime = durToStr(answer[18..$-2]);
      int
        sec = answer[18..$-2].to!int,
        step = strToDur(mplayer.currentTrack.duration) / 40,
        newPos = sec / step;
      if (mplayer.position != newPos) {
        mplayer.position    = newPos;
        auto newProgress  = mplayer.stockProgress.dup; 
        newProgress[newPos] = '|';
        mplayer.realProgress = newProgress.to!string;
      }
    }
    playtimeUpdated = true;
  }

  string get(string cmd) {
    if (mplayer.output.length != 0) {
      send(cmd);
      if (mplayer.output[$-1].canFind("ANS")) return mplayer.output[$-1];
      else return "";
    } else
      return "";
  }

  ListElement[] getMplayerUI(int cols) {
    ListElement[] playerUI;
    playerUI ~= ListElement(" ".replicate((cols-16)/2-mplayer.currentTrack.artist.utfLength/2)~mplayer.currentTrack.artist);
    playerUI ~= ListElement(" ".replicate((cols-16)/2-mplayer.currentTrack.title.utfLength/2)~mplayer.currentTrack.title);
    playerUI ~= ListElement(center(mplayer.currentTrack.playtime ~ " / " ~ mplayer.currentTrack.duration, cols-16, ' '));
    playerUI ~= ListElement(center("[" ~ mplayer.realProgress ~ "] ⟲ ⤮", cols-16, ' '));
    playerUI ~= ListElement("");
    return playerUI;
  }

  void runPlayer() {
    auto pipe = pipeProcess("sh", Redirect.stdin | Redirect.stdout);
    pipe.stdin.writeln("cat /dev/stdin | mplayer -slave -idle 2> /dev/null");
    pipe.stdin.flush;
    stdinPipe = &(pipe.stdin);
    mplayer.isInit = true;
    mplayer.currentTrack.playtime = "0:00";
    foreach (line; pipe.stdout.byLine) output ~= line.idup;
    mplayerExit = true;
  }

  void listenStdout() {
    while (!mplayerExit) {
      if (output.length != lastOutputLn) {
        lastOutputLn = output.length;
        if (mplayer.musicState) setPlaytime(get("get_time_pos"));
      }
      Thread.sleep(listenWait);
    }
  }

  void startPlayer() {
    listen = new Thread(&listenStdout);
    listen.start;
    this.start;
  }

}
