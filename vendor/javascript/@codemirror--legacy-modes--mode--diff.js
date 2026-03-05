// @codemirror/legacy-modes/mode/diff@6.5.2 downloaded from https://ga.jspm.io/npm:@codemirror/legacy-modes@6.5.2/mode/diff.js

var e={"+":"inserted","-":"deleted","@":"meta"};const r={name:"diff",token:function(r){var n=r.string.search(/[\t ]+?$/);if(!r.sol()||n===0){r.skipToEnd();return("error "+(e[r.string.charAt(0)]||"")).replace(/ $/,"")}var t=e[r.peek()]||r.skipToEnd();n===-1?r.skipToEnd():r.pos=n;return t}};export{r as diff};

