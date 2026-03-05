// @codemirror/legacy-modes/mode/brainfuck@6.5.2 downloaded from https://ga.jspm.io/npm:@codemirror/legacy-modes@6.5.2/mode/brainfuck.js

var e="><+-.,[]".split("");const t={name:"brainfuck",startState:function(){return{commentLine:false,left:0,right:0,commentLoop:false}},token:function(t,n){if(t.eatSpace())return null;t.sol()&&(n.commentLine=false);var r=t.next().toString();if(e.indexOf(r)===-1){n.commentLine=true;t.eol()&&(n.commentLine=false);return"comment"}if(n.commentLine===true){t.eol()&&(n.commentLine=false);return"comment"}if(r==="]"||r==="["){r==="["?n.left++:n.right++;return"bracket"}if(r==="+"||r==="-")return"keyword";if(r==="<"||r===">")return"atom";if(r==="."||r===",")return"def";t.eol()&&(n.commentLine=false)}};export{t as brainfuck};

