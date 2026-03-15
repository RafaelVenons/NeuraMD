// graphology-traversal@0.3.1 downloaded from https://ga.jspm.io/npm:graphology-traversal@0.3.1/index.js

import*as r from"graphology-utils/is-graph";import*as a from"graphology-indices/bfs-queue";import*as e from"graphology-indices/dfs-stack";var t="undefined"!==typeof globalThis?globalThis:"undefined"!==typeof self?self:global;var o={};function TraversalRecord$2(r,a,e){(this||t).node=r;(this||t).attributes=a;(this||t).depth=e}function capitalize$2(r){return r[0].toUpperCase()+r.slice(1)}o.TraversalRecord=TraversalRecord$2;o.capitalize=capitalize$2;var i="default"in r?r.default:r;var n="default"in a?a.default:a;var s={};var f=i;var d=n;var l=o;var u=l.TraversalRecord;var c=l.capitalize;
/**
 * BFS traversal in the given graph using a callback function
 *
 * @param {Graph}    graph        - Target graph.
 * @param {string}   startingNode - Optional Starting node.
 * @param {function} callback     - Iteration callback.
 * @param {object}   options      - Options:
 * @param {string}     mode         - Traversal mode.
 */function abstractBfs(r,a,e,t){t=t||{};if(!f(r))throw new Error("graphology-traversal/bfs: expecting a graphology instance.");if("function"!==typeof e)throw new Error("graphology-traversal/bfs: given callback is not a function.");if(0!==r.order){var o=new d(r);var i=r["forEach"+c(t.mode||"outbound")+"Neighbor"].bind(r);var n;n=null===a?o.forEachNodeYetUnseen.bind(o):function(e){a=""+a;e(a,r.getNodeAttributes(a))};var s,l;n((function(r,a){o.pushWith(r,new u(r,a,0));while(0!==o.size){s=o.shift();l=e(s.node,s.attributes,s.depth);true!==l&&i(s.node,visit)}}))}function visit(r,a){o.pushWith(r,new u(r,a,s.depth+1))}}s.bfs=function(r,a,e){return abstractBfs(r,null,a,e)};s.bfsFromNode=abstractBfs;var v="default"in r?r.default:r;var h="default"in e?e.default:e;var p={};var b=v;var g=h;var m=o;var w=m.TraversalRecord;var N=m.capitalize;
/**
 * DFS traversal in the given graph using a callback function
 *
 * @param {Graph}    graph        - Target graph.
 * @param {string}   startingNode - Optional Starting node.
 * @param {function} callback     - Iteration callback.
 * @param {object}   options      - Options:
 * @param {string}     mode         - Traversal mode.
 */function abstractDfs(r,a,e,t){t=t||{};if(!b(r))throw new Error("graphology-traversal/dfs: expecting a graphology instance.");if("function"!==typeof e)throw new Error("graphology-traversal/dfs: given callback is not a function.");if(0!==r.order){var o=new g(r);var i=r["forEach"+N(t.mode||"outbound")+"Neighbor"].bind(r);var n;n=null===a?o.forEachNodeYetUnseen.bind(o):function(e){a=""+a;e(a,r.getNodeAttributes(a))};var s,f;n((function(r,a){o.pushWith(r,new w(r,a,0));while(0!==o.size){s=o.pop();f=e(s.node,s.attributes,s.depth);true!==f&&i(s.node,visit)}}))}function visit(r,a){o.pushWith(r,new w(r,a,s.depth+1))}}p.dfs=function(r,a,e){return abstractDfs(r,null,a,e)};p.dfsFromNode=abstractDfs;var y={};var E=s;var F=p;y.bfs=E.bfs;y.bfsFromNode=E.bfsFromNode;y.dfs=F.dfs;y.dfsFromNode=F.dfsFromNode;const z=y.bfs,T=y.bfsFromNode,R=y.dfs,W=y.dfsFromNode;export{z as bfs,T as bfsFromNode,y as default,R as dfs,W as dfsFromNode};

