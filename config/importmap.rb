# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/editor", under: "editor"
pin_all_from "app/javascript/graph", under: "graph"
pin_all_from "app/javascript/lib", under: "lib"
pin "@codemirror/state", to: "@codemirror--state.js" # @6.5.4
pin "@marijn/find-cluster-break", to: "@marijn--find-cluster-break.js" # @1.0.2
pin "@codemirror/commands", to: "@codemirror--commands.js" # @6.10.2
pin "@codemirror/lang-markdown", to: "@codemirror--lang-markdown.js" # @6.5.0
pin "@codemirror/language", to: "@codemirror--language.js" # @6.12.2
pin "@codemirror/search", to: "@codemirror--search.js" # @6.6.0
pin "@codemirror/view", to: "@codemirror--view.js" # @6.39.16
pin "@lezer/common", to: "@lezer--common.js" # @1.5.1
pin "@lezer/highlight", to: "@lezer--highlight.js" # @1.2.3
pin "@lezer/lr", to: "@lezer--lr.js" # @1.4.8
pin "@lezer/markdown", to: "@lezer--markdown.js" # @1.6.3
pin "marked" # @17.0.3
pin "@codemirror/autocomplete", to: "@codemirror--autocomplete.js" # @6.20.1
pin "@codemirror/lang-css", to: "@codemirror--lang-css.js" # @6.3.1
pin "@codemirror/lang-html", to: "@codemirror--lang-html.js" # @6.4.11
pin "@codemirror/lang-javascript", to: "@codemirror--lang-javascript.js" # @6.2.4
pin "@lezer/css", to: "@lezer--css.js" # @1.3.0
pin "@lezer/html", to: "@lezer--html.js" # @1.3.13
pin "@lezer/javascript", to: "@lezer--javascript.js" # @1.5.4
pin "crelt" # @1.0.6
pin "style-mod" # @4.1.3
pin "w3c-keyname" # @2.2.8
pin "@codemirror/language-data", to: "@codemirror--language-data.js" # @6.5.2
pin "@codemirror/theme-one-dark", to: "@codemirror--theme-one-dark.js" # @6.1.2
pin "@codemirror/lang-angular", to: "@codemirror--lang-angular.js" # @0.1.4
pin "@codemirror/lang-cpp", to: "@codemirror--lang-cpp.js" # @6.0.3
pin "@codemirror/lang-go", to: "@codemirror--lang-go.js" # @6.0.1
pin "@codemirror/lang-java", to: "@codemirror--lang-java.js" # @6.0.2
pin "@codemirror/lang-jinja", to: "@codemirror--lang-jinja.js" # @6.0.0
pin "@codemirror/lang-json", to: "@codemirror--lang-json.js" # @6.0.2
pin "@codemirror/lang-less", to: "@codemirror--lang-less.js" # @6.0.2
pin "@codemirror/lang-liquid", to: "@codemirror--lang-liquid.js" # @6.3.2
pin "@codemirror/lang-php", to: "@codemirror--lang-php.js" # @6.0.2
pin "@codemirror/lang-python", to: "@codemirror--lang-python.js" # @6.2.1
pin "@codemirror/lang-rust", to: "@codemirror--lang-rust.js" # @6.0.1
pin "@codemirror/lang-sass", to: "@codemirror--lang-sass.js" # @6.0.2
pin "@codemirror/lang-sql", to: "@codemirror--lang-sql.js" # @6.10.0
pin "@codemirror/lang-vue", to: "@codemirror--lang-vue.js" # @0.1.3
pin "@codemirror/lang-wast", to: "@codemirror--lang-wast.js" # @6.0.2
pin "@codemirror/lang-xml", to: "@codemirror--lang-xml.js" # @6.1.0
pin "@codemirror/lang-yaml", to: "@codemirror--lang-yaml.js" # @6.1.2
pin "@codemirror/legacy-modes/mode/apl", to: "@codemirror--legacy-modes--mode--apl.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/asciiarmor", to: "@codemirror--legacy-modes--mode--asciiarmor.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/asn1", to: "@codemirror--legacy-modes--mode--asn1.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/asterisk", to: "@codemirror--legacy-modes--mode--asterisk.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/brainfuck", to: "@codemirror--legacy-modes--mode--brainfuck.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/clike", to: "@codemirror--legacy-modes--mode--clike.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/clojure", to: "@codemirror--legacy-modes--mode--clojure.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/cmake", to: "@codemirror--legacy-modes--mode--cmake.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/cobol", to: "@codemirror--legacy-modes--mode--cobol.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/coffeescript", to: "@codemirror--legacy-modes--mode--coffeescript.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/commonlisp", to: "@codemirror--legacy-modes--mode--commonlisp.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/crystal", to: "@codemirror--legacy-modes--mode--crystal.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/css", to: "@codemirror--legacy-modes--mode--css.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/cypher", to: "@codemirror--legacy-modes--mode--cypher.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/d", to: "@codemirror--legacy-modes--mode--d.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/diff", to: "@codemirror--legacy-modes--mode--diff.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/dockerfile", to: "@codemirror--legacy-modes--mode--dockerfile.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/dtd", to: "@codemirror--legacy-modes--mode--dtd.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/dylan", to: "@codemirror--legacy-modes--mode--dylan.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/ebnf", to: "@codemirror--legacy-modes--mode--ebnf.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/ecl", to: "@codemirror--legacy-modes--mode--ecl.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/eiffel", to: "@codemirror--legacy-modes--mode--eiffel.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/elm", to: "@codemirror--legacy-modes--mode--elm.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/erlang", to: "@codemirror--legacy-modes--mode--erlang.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/factor", to: "@codemirror--legacy-modes--mode--factor.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/fcl", to: "@codemirror--legacy-modes--mode--fcl.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/forth", to: "@codemirror--legacy-modes--mode--forth.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/fortran", to: "@codemirror--legacy-modes--mode--fortran.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/gas", to: "@codemirror--legacy-modes--mode--gas.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/gherkin", to: "@codemirror--legacy-modes--mode--gherkin.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/groovy", to: "@codemirror--legacy-modes--mode--groovy.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/haskell", to: "@codemirror--legacy-modes--mode--haskell.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/haxe", to: "@codemirror--legacy-modes--mode--haxe.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/http", to: "@codemirror--legacy-modes--mode--http.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/idl", to: "@codemirror--legacy-modes--mode--idl.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/javascript", to: "@codemirror--legacy-modes--mode--javascript.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/julia", to: "@codemirror--legacy-modes--mode--julia.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/livescript", to: "@codemirror--legacy-modes--mode--livescript.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/lua", to: "@codemirror--legacy-modes--mode--lua.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/mathematica", to: "@codemirror--legacy-modes--mode--mathematica.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/mbox", to: "@codemirror--legacy-modes--mode--mbox.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/mirc", to: "@codemirror--legacy-modes--mode--mirc.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/mllike", to: "@codemirror--legacy-modes--mode--mllike.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/modelica", to: "@codemirror--legacy-modes--mode--modelica.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/mscgen", to: "@codemirror--legacy-modes--mode--mscgen.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/mumps", to: "@codemirror--legacy-modes--mode--mumps.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/nginx", to: "@codemirror--legacy-modes--mode--nginx.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/nsis", to: "@codemirror--legacy-modes--mode--nsis.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/ntriples", to: "@codemirror--legacy-modes--mode--ntriples.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/octave", to: "@codemirror--legacy-modes--mode--octave.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/oz", to: "@codemirror--legacy-modes--mode--oz.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/pascal", to: "@codemirror--legacy-modes--mode--pascal.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/perl", to: "@codemirror--legacy-modes--mode--perl.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/pig", to: "@codemirror--legacy-modes--mode--pig.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/powershell", to: "@codemirror--legacy-modes--mode--powershell.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/properties", to: "@codemirror--legacy-modes--mode--properties.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/protobuf", to: "@codemirror--legacy-modes--mode--protobuf.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/pug", to: "@codemirror--legacy-modes--mode--pug.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/puppet", to: "@codemirror--legacy-modes--mode--puppet.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/python", to: "@codemirror--legacy-modes--mode--python.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/q", to: "@codemirror--legacy-modes--mode--q.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/r", to: "@codemirror--legacy-modes--mode--r.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/rpm", to: "@codemirror--legacy-modes--mode--rpm.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/ruby", to: "@codemirror--legacy-modes--mode--ruby.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/sas", to: "@codemirror--legacy-modes--mode--sas.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/scheme", to: "@codemirror--legacy-modes--mode--scheme.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/shell", to: "@codemirror--legacy-modes--mode--shell.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/sieve", to: "@codemirror--legacy-modes--mode--sieve.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/smalltalk", to: "@codemirror--legacy-modes--mode--smalltalk.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/solr", to: "@codemirror--legacy-modes--mode--solr.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/sparql", to: "@codemirror--legacy-modes--mode--sparql.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/spreadsheet", to: "@codemirror--legacy-modes--mode--spreadsheet.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/sql", to: "@codemirror--legacy-modes--mode--sql.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/stex", to: "@codemirror--legacy-modes--mode--stex.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/stylus", to: "@codemirror--legacy-modes--mode--stylus.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/swift", to: "@codemirror--legacy-modes--mode--swift.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/tcl", to: "@codemirror--legacy-modes--mode--tcl.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/textile", to: "@codemirror--legacy-modes--mode--textile.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/tiddlywiki", to: "@codemirror--legacy-modes--mode--tiddlywiki.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/tiki", to: "@codemirror--legacy-modes--mode--tiki.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/toml", to: "@codemirror--legacy-modes--mode--toml.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/troff", to: "@codemirror--legacy-modes--mode--troff.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/ttcn", to: "@codemirror--legacy-modes--mode--ttcn.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/ttcn-cfg", to: "@codemirror--legacy-modes--mode--ttcn-cfg.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/turtle", to: "@codemirror--legacy-modes--mode--turtle.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/vb", to: "@codemirror--legacy-modes--mode--vb.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/vbscript", to: "@codemirror--legacy-modes--mode--vbscript.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/velocity", to: "@codemirror--legacy-modes--mode--velocity.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/verilog", to: "@codemirror--legacy-modes--mode--verilog.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/vhdl", to: "@codemirror--legacy-modes--mode--vhdl.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/webidl", to: "@codemirror--legacy-modes--mode--webidl.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/xquery", to: "@codemirror--legacy-modes--mode--xquery.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/yacas", to: "@codemirror--legacy-modes--mode--yacas.js" # @6.5.2
pin "@codemirror/legacy-modes/mode/z80", to: "@codemirror--legacy-modes--mode--z80.js" # @6.5.2
pin "@lezer/cpp", to: "@lezer--cpp.js" # @1.1.5
pin "@lezer/go", to: "@lezer--go.js" # @1.0.1
pin "@lezer/java", to: "@lezer--java.js" # @1.1.3
pin "@lezer/json", to: "@lezer--json.js" # @1.0.3
pin "@lezer/php", to: "@lezer--php.js" # @1.0.5
pin "@lezer/python", to: "@lezer--python.js" # @1.1.18
pin "@lezer/rust", to: "@lezer--rust.js" # @1.0.2
pin "@lezer/sass", to: "@lezer--sass.js" # @1.1.0
pin "@lezer/xml", to: "@lezer--xml.js" # @1.0.6
pin "@lezer/yaml", to: "@lezer--yaml.js" # @1.0.4
# Specialized preview renderers (lazy-loaded)
pin "mermaid", to: "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs", preload: false
pin "katex", to: "https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.mjs", preload: false

pin "graphology" # @0.26.0
pin "graphology-layout" # @0.6.1
pin "graphology-layout/circlepack", to: "circlepack.js"
pin "graphology-layout/circular", to: "circular.js"
pin "graphology-layout/random", to: "random.js"
pin "graphology-layout-forceatlas2" # @0.10.1
pin "graphology-layout-forceatlas2/_/987d9be9", to: "_/987d9be9.js"
pin "graphology-layout-noverlap" # @0.4.2
pin "graphology-layout-noverlap/_/a72dd12e", to: "_/a72dd12e.js"
pin "graphology-traversal" # @0.3.1
pin "sigma" # @3.0.2
pin "sigma/rendering", to: "rendering/dist/sigma-rendering.esm.js"
pin "sigma/utils", to: "utils/dist/sigma-utils.esm.js"
pin "sigma/settings", to: "settings/dist/sigma-settings.esm.js"
pin "sigma/types", to: "types/dist/sigma-types.esm.js"
pin "sigma/_/B0DcsMff", to: "_/B0DcsMff.js"
pin "sigma/_/BZp2-4cL", to: "_/BZp2-4cL.js"
pin "sigma/_/C-W17dgt", to: "_/C-W17dgt.js"
pin "sigma/_/kE2EJL4M", to: "_/kE2EJL4M.js"
pin "sigma/_/pV8YYdtx", to: "_/pV8YYdtx.js"
pin "sigma/dist/colors", to: "dist/colors-beb06eb2.esm.js"
pin "sigma/dist/data", to: "dist/data-11df7124.esm.js"
pin "sigma/dist/index", to: "dist/index-236c62ad.esm.js"
pin "sigma/dist/inherits", to: "dist/inherits-d1a1e29b.esm.js"
pin "sigma/dist/normalization", to: "dist/normalization-be445518.esm.js"
pin "events" # @3.3.0
pin "graphology-indices/bfs-queue", to: "graphology-indices--bfs-queue.js" # @0.17.0
pin "graphology-indices/dfs-stack", to: "graphology-indices--dfs-stack.js" # @0.17.0
pin "graphology-utils/defaults", to: "graphology-utils--defaults.js" # @2.5.2
pin "graphology-utils/getters", to: "graphology-utils--getters.js" # @2.5.2
pin "graphology-utils/is-graph", to: "graphology-utils--is-graph.js" # @2.5.2
pin "mnemonist/fixed-deque", to: "mnemonist--fixed-deque.js" # @0.39.8
pin "mnemonist/_/l6VHs6WY", to: "_/l6VHs6WY.js"
pin "mnemonist/utils/typed-arrays", to: "utils/typed-arrays.js"
pin "obliterator/foreach", to: "obliterator--foreach.js" # @2.0.5
pin "obliterator/_/TukZPN2J", to: "_/TukZPN2J.js"
pin "obliterator/iterator", to: "obliterator--iterator.js" # @2.0.5
pin "pandemonium/shuffle-in-place", to: "pandemonium--shuffle-in-place.js" # @2.4.1
pin "@xterm/addon-fit", to: "@xterm--addon-fit.js" # @0.11.0
pin "@xterm/xterm", to: "@xterm--xterm.js" # @6.0.0
pin "@rails/actioncable", to: "@rails--actioncable.js" # @8.1.300
