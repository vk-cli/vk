import std.process, std.stdio, std.string, std.algorithm, std.file, std.regex, std.conv;


void main() {
  const ver = "0.7.2";
  immutable string
    lastCommitHash = matchFirst(executeShell("git log -1").output, regex(r"(?:^commit\s+)([0-9a-f]{40})"))[1][0..7],
    currentBranch = matchFirst(executeShell("git status").output, regex(r"(?:^On branch\s+)(.+)"))[1];

  auto fname = "source/utils.d";
  auto t = readText(fname).split("\n");
  auto r = regex("(^\\s*currentVersion\\s*=\\s*\")(.+)(\"\\s*;)");
  foreach(ref l; t) {
    auto m = matchFirst(l, r);
    if(m.length == 4) {
      auto v = ver ~ "-" ~ currentBranch ~ "-" ~ lastCommitHash;
      writeln("version string: " ~ v);
      l = m[1] ~ v ~ m[3];
      break;
    }
  }
  auto f = File(fname, "w");
  f.write(t.join("\n"));
  f.close();
}