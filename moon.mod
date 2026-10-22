// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "Mitsuha11zz/chronolens"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/Mitsuha11zz/ChronoLens-"

license = "Apache-2.0"

keywords = [ "clock-offset", "log-analysis", "difference-constraints" ]

preferred_target = "native"

description = "Offline clock-offset constraint diagnosis for distributed logs."

import {
  "moonbitlang/x@0.5.5",
}
