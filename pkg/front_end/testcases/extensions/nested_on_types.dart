// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.9

class A<T> {}

extension Extension<T> on A<A<T>> {
  method1() {}

  method2<A>(A a) {}
}

main() {
}