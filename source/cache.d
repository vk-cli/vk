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

module cache;

import std.stdio, std.conv, std.algorithm, std.array;
import vkapi, utils;

class Cache(T) { // test-impl for cache
	immutable typestring = T.stringof;

	T[] midcache;

	bool hasCacheFor(int pos, int count) {
		return (midcache.length >= pos+count);
	}

	T[] getCache(int pos, int count) {
		if(!hasCacheFor(pos, count)) throw new InternalException(-1, "no cache found for this range " ~ pos.to!string ~ "(" ~ count.to!string ~ ")");
		return midcache[pos..(pos+count)];
	}
}