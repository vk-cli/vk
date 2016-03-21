import std.process, std.stdio, std.string, std.array, std.algorithm, std.conv;
import app, utils;

struct Track {
  string artist, title, duration, playtime;
}

struct MusicPlayer {
  File delegate() stdinPipe;
  Track currentTrack;
  string currentPlayingTrack;
  bool musicState = false;
  Track[] playlist;
  string[] output;
}

__gshared MusicPlayer mplayer;

void exitMplayer() {
  send("quit");
}

void send(string cmd) {
  if (mplayer.currentPlayingTrack != ""){
     auto stdin = mplayer.stdinPipe();
     stdin.writeln(cmd);
     stdin.flush();
  }
}

string durToStr(string duration) {
  int intDuration = duration.to!int;
  int min = intDuration / 60;
  int sec = intDuration - (60*min);
  return min.to!string ~ ":" ~ sec.tzr;
}

void setPlaytime(string answer) {
  if (answer != "") mplayer.currentTrack.playtime = answer[18..$-2].durToStr;
  else mplayer.currentTrack.playtime = "0:00";
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
  playerUI ~= ListElement(center("[========================|===============] ⟲ ⤮", cols-16, ' '));
  playerUI ~= ListElement("");
  return playerUI;
}

void startPlayer(string url) {
  auto pipe = pipeProcess("sh", Redirect.stdin | Redirect.stdout);
  pipe.stdin.writeln("cat /dev/stdin | mplayer -slave -idle " ~ url ~ " 2> /dev/null");
  pipe.stdin.flush;
  mplayer.stdinPipe = &(pipe.stdin);
  foreach (line; pipe.stdout.byLine) {
    mplayer.output ~= line.idup;
    get("get_time_pos").setPlaytime;
  }
}