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

import std.process, std.stdio, std.string, std.algorithm,
       std.file, std.regex, std.conv;

void main() {
  const versionNum = "0.7.6";
  const releaseFlag = false;
  string
    lastCommitHash,
    currentBranch;

  if(!releaseFlag) {
    lastCommitHash = matchFirst(executeShell("git log -1").output, regex(r"(?:^commit\s+)([0-9a-f]{40})"))[1][0..7];
    currentBranch = matchFirst(executeShell("git status").output, regex(r"(?:^On branch\s+)(.+)"))[1];
  }

  auto verTemplate = "
module vkversion;

const string
  currentVersion = \"master\";

";

  auto fileName = "source/vkversion.d";
  string[] text;

  if(!exists(fileName)) text = verTemplate.split("\n");
  else text = readText(fileName).split("\n");

  auto reg = regex("(^\\s*currentVersion\\s*=\\s*\")(.+)(\"\\s*;)");
  foreach (ref line; text) {
    auto match = matchFirst(line, reg);
    if (match.length == 4) {
      auto versionString = releaseFlag ? versionNum : versionNum ~ "-" ~ currentBranch ~ "-" ~ lastCommitHash;
      writeln("version string: " ~ versionString);
      line = match[1] ~ versionString ~ match[3];
      break;
    }
  }
  auto f = File(fileName, "w");
  f.write(text.join("\n"));
  f.close;
}
