// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*library: 
 a_pre_fragments=[p1: {units: [1{lib}], usedBy: [], needs: []}],
 b_finalized_fragments=[f1: [1{lib}]],
 c_steps=[lib=(f1)]
*/

import "lib.dart" deferred as lib;

/*member: main:member_unit=main{}*/
void main() {
  lib.loadLibrary().then(/*closure_unit=main{}*/ (_) {
    lib.A2();
    lib.B2();
    lib.C3();
    lib.D3(10);
    lib.G();
  });
}
