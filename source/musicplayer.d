import std.process, std.stdio, std.string, std.array;
import app;

struct Track {
  string artist, title, duration;
}

struct MusicPlayer {
  Track[] playlist;
  bool musicState = false;
  Track currentTrack;
  string currentPlayingTrack;
}

MusicPlayer mplayer;

void initMplayer() {
  auto fifo = executeShell("mkfifo /tmp/mplayerfifo");
  if (fifo.status != 0) writeln("Failed to create fifo for mplayer");
}

void exitMplayer() {
  send("quit");
  auto fifo = executeShell("rm /tmp/mplayerfifo");
}

void send(string cmd) {
  executeShell(`echo "` ~ cmd ~ `" > /tmp/mplayerfifo`);
}

ListElement[] getMplayerUI(int cols) {
  ListElement[] playerUI;
  playerUI ~= ListElement(" ".replicate((cols-16)/2-mplayer.currentTrack.artist.utfLength/2)~mplayer.currentTrack.artist);
  playerUI ~= ListElement(" ".replicate((cols-16)/2-mplayer.currentTrack.title.utfLength/2)~mplayer.currentTrack.title);
  playerUI ~= ListElement(center("0:00 / " ~ mplayer.currentTrack.duration, cols-16, ' '));
  playerUI ~= ListElement(center("[========================|==========]", cols-16, ' '));
  playerUI ~= ListElement("");
  return playerUI;
}

void startPlayer(string url) {
  auto mpl = spawnShell("mplayer -slave -idle -input file=/tmp/mplayerfifo " ~ url ~ " > /dev/null 2> /dev/null");
}