import std.process, std.stdio, std.string, std.algorithm, std.file;


void main() {
  string
    lastCommitHash = executeShell("git log -1").output.splitLines[0][7..14],
    currentBranch  = executeShell("git branch").output.splitLines.filter!(e => e.startsWith("*")).front[2..$];


  auto f = File("source/utils.d", "rw");
  while (!f.eof) {
    auto line = f.readln;
    if (e.startsWith("  currentVersion")) line.writeln;
  }
}