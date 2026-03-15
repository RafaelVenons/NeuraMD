// graphology-layout@0.6.1 downloaded from https://ga.jspm.io/npm:graphology-layout@0.6.1/index.js

import r from"graphology-layout/circlepack";import a from"graphology-layout/circular";import i from"graphology-layout/random";import*as n from"graphology-utils/defaults";import*as o from"graphology-utils/is-graph";import"pandemonium/shuffle-in-place";var t="default"in n?n.default:n;var e="default"in o?o.default:o;var s={};var f=t;var l=e;var c=Math.PI/180;var u={dimensions:["x","y"],centeredOnZero:false,degrees:false};
/**
 * Abstract function for rotating a graph's coordinates.
 *
 * @param  {Graph}    graph          - Target  graph.
 * @param  {number}   angle          - Rotation angle.
 * @param  {object}   [options]      - Options.
 * @return {object}                  - The positions by node.
 */function genericRotation(r,a,i,n){if(!l(a))throw new Error("graphology-layout/rotation: the given graph is not a valid graphology instance.");n=f(n,u);n.degrees&&(i*=c);var o=n.dimensions;if(!Array.isArray(o)||2!==o.length)throw new Error("graphology-layout/random: given dimensions are invalid.");if(0===a.order){if(r)return;return{}}var t=o[0];var e=o[1];var s=0;var v=0;if(!n.centeredOnZero){var d=Infinity;var g=-Infinity;var m=Infinity;var p=-Infinity;a.forEachNode((function(r,a){var i=a[t];var n=a[e];i<d&&(d=i);i>g&&(g=i);n<m&&(m=n);n>p&&(p=n)}));s=(d+g)/2;v=(m+p)/2}var h=Math.cos(i);var y=Math.sin(i);function assignPosition(r){var a=r[t];var i=r[e];r[t]=s+(a-s)*h-(i-v)*y;r[e]=v+(a-s)*y+(i-v)*h;return r}if(!r){var E={};a.forEachNode((function(r,a){var i={};i[t]=a[t];i[e]=a[e];E[r]=assignPosition(i)}));return E}a.updateEachNodeAttributes((function(r,a){assignPosition(a);return a}),{attributes:o})}var v=genericRotation.bind(null,false);v.assign=genericRotation.bind(null,true);s=v;var d=s;var g={};g.circlepack=r;g.circular=a;g.random=i;g.rotation=d;const m=g.circlepack,p=g.circular,h=g.random,y=g.rotation;export{m as circlepack,p as circular,g as default,h as random,y as rotation};
