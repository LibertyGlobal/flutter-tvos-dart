// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Regression test for dartbug.com/47822

mixin M {
  int x = (() => 7)();
}

class C with M {}

main() {
  print(C().x);
}
