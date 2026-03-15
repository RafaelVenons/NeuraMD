import*as a from"graphology-utils/defaults";import*as r from"graphology-utils/is-graph";var n="default"in a?a.default:a;var o="default"in r?r.default:r;var i={};var t=n;var e=o;var s={dimensions:["x","y"],center:.5,rng:Math.random,scale:1};
/**
 * Abstract function running the layout.
 *
 * @param  {Graph}    graph          - Target  graph.
 * @param  {object}   [options]      - Options:
 * @param  {array}      [dimensions] - List of dimensions of the layout.
 * @param  {number}     [center]     - Center of the layout.
 * @param  {function}   [rng]        - Custom RNG function to be used.
 * @param  {number}     [scale]      - Scale of the layout.
 * @return {object}                  - The positions by node.
 */function genericRandomLayout(a,r,n){if(!e(r))throw new Error("graphology-layout/random: the given graph is not a valid graphology instance.");n=t(n,s);var o=n.dimensions;if(!Array.isArray(o)||o.length<1)throw new Error("graphology-layout/random: given dimensions are invalid.");var i=o.length;var l=n.center;var u=n.rng;var g=n.scale;var d=(l-.5)*g;function assignPosition(a){for(var r=0;r<i;r++)a[o[r]]=u()*g+d;return a}if(!a){var v={};r.forEachNode((function(a){v[a]=assignPosition({})}));return v}r.updateEachNodeAttributes((function(a,r){assignPosition(r);return r}),{attributes:o})}var l=genericRandomLayout.bind(null,false);l.assign=genericRandomLayout.bind(null,true);i=l;var u=i;export{u as default};

//# sourceMappingURL=random.js.map