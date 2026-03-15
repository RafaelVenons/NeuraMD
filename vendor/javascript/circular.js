import*as r from"graphology-utils/defaults";import*as a from"graphology-utils/is-graph";var i="default"in r?r.default:r;var n="default"in a?a.default:a;var o={};var t=i;var e=n;var s={dimensions:["x","y"],center:.5,scale:1};
/**
 * Abstract function running the layout.
 *
 * @param  {Graph}    graph          - Target  graph.
 * @param  {object}   [options]      - Options:
 * @param  {object}     [attributes] - Attributes names to map.
 * @param  {number}     [center]     - Center of the layout.
 * @param  {number}     [scale]      - Scale of the layout.
 * @return {object}                  - The positions by node.
 */function genericCircularLayout(r,a,i){if(!e(a))throw new Error("graphology-layout/random: the given graph is not a valid graphology instance.");i=t(i,s);var n=i.dimensions;if(!Array.isArray(n)||2!==n.length)throw new Error("graphology-layout/random: given dimensions are invalid.");var o=i.center;var u=i.scale;var l=2*Math.PI;var g=(o-.5)*u;var v=a.order;var d=n[0];var c=n[1];function assignPosition(r,a){a[d]=u*Math.cos(r*l/v)+g;a[c]=u*Math.sin(r*l/v)+g;return a}var f=0;if(!r){var h={};a.forEachNode((function(r){h[r]=assignPosition(f++,{})}));return h}a.updateEachNodeAttributes((function(r,a){assignPosition(f++,a);return a}),{attributes:n})}var u=genericCircularLayout.bind(null,false);u.assign=genericCircularLayout.bind(null,true);o=u;var l=o;export{l as default};

//# sourceMappingURL=circular.js.map