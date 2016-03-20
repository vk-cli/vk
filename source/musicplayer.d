import std.process, std.stdio, std.string, std.array;
import app;

struct Track {
  string artist, title, duration;
}

struct MusicPlayer {
  File stdinPipe;
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
  if (mplayer.currentPlayingTrack != "") mplayer.stdinPipe.writeln(cmd);
}

ListElement[] getMplayerUI(int cols) {
  ListElement[] playerUI;
  playerUI ~= ListElement(" ".replicate((cols-16)/2-mplayer.currentTrack.artist.utfLength/2)~mplayer.currentTrack.artist);
  playerUI ~= ListElement(" ".replicate((cols-16)/2-mplayer.currentTrack.title.utfLength/2)~mplayer.currentTrack.title);
  playerUI ~= ListElement(center("0:00 / " ~ mplayer.currentTrack.duration, cols-16, ' '));
  playerUI ~= ListElement(center("[========================|==========] ⟲ ⤮", cols-16, ' '));
  playerUI ~= ListElement("");
  return playerUI;
}

void startPlayer(string url) {
  auto pipe = pipeProcess("sh", Redirect.stdin | Redirect.stdout);
  pipe.stdin.writeln("mplayer -slave -idle " ~ url ~ " 2> /dev/null");
  pipe.stdin.flush;
  mplayer.stdinPipe = pipe.stdin;
  foreach (line; pipe.stdout.byLine) mplayer.output ~= line.idup;
}
