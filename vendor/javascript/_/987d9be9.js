var e={};var t=10;var n=3;
/**
 * Very simple Object.assign-like function.
 *
 * @param  {object} target       - First object.
 * @param  {object} [...objects] - Objects to merge.
 * @return {object}
 */e.assign=function(e){e=e||{};var t,n,a,o=Array.prototype.slice.call(arguments).slice(1);for(t=0,a=o.length;t<a;t++)if(o[t])for(n in o[t])e[n]=o[t][n];return e};
/**
 * Function used to validate the given settings.
 *
 * @param  {object}      settings - Settings to validate.
 * @return {object|null}
 */e.validateSettings=function(e){return"linLogMode"in e&&"boolean"!==typeof e.linLogMode?{message:"the `linLogMode` setting should be a boolean."}:"outboundAttractionDistribution"in e&&"boolean"!==typeof e.outboundAttractionDistribution?{message:"the `outboundAttractionDistribution` setting should be a boolean."}:"adjustSizes"in e&&"boolean"!==typeof e.adjustSizes?{message:"the `adjustSizes` setting should be a boolean."}:"edgeWeightInfluence"in e&&"number"!==typeof e.edgeWeightInfluence?{message:"the `edgeWeightInfluence` setting should be a number."}:!("scalingRatio"in e)||"number"===typeof e.scalingRatio&&e.scalingRatio>=0?"strongGravityMode"in e&&"boolean"!==typeof e.strongGravityMode?{message:"the `strongGravityMode` setting should be a boolean."}:!("gravity"in e)||"number"===typeof e.gravity&&e.gravity>=0?"slowDown"in e&&!("number"===typeof e.slowDown||e.slowDown>=0)?{message:"the `slowDown` setting should be a number >= 0."}:"barnesHutOptimize"in e&&"boolean"!==typeof e.barnesHutOptimize?{message:"the `barnesHutOptimize` setting should be a boolean."}:!("barnesHutTheta"in e)||"number"===typeof e.barnesHutTheta&&e.barnesHutTheta>=0?null:{message:"the `barnesHutTheta` setting should be a number >= 0."}:{message:"the `gravity` setting should be a number >= 0."}:{message:"the `scalingRatio` setting should be a number >= 0."}};
/**
 * Function generating a flat matrix for both nodes & edges of the given graph.
 *
 * @param  {Graph}    graph         - Target graph.
 * @param  {function} getEdgeWeight - Edge weight getter function.
 * @return {object}                 - Both matrices.
 */e.graphToByteArrays=function(e,a){var o=e.order;var r=e.size;var i={};var s;var u=new Float32Array(o*t);var l=new Float32Array(r*n);s=0;e.forEachNode((function(e,n){i[e]=s;u[s]=n.x;u[s+1]=n.y;u[s+2]=0;u[s+3]=0;u[s+4]=0;u[s+5]=0;u[s+6]=1;u[s+7]=1;u[s+8]=n.size||1;u[s+9]=n.fixed?1:0;s+=t}));s=0;e.forEachEdge((function(e,t,o,r,g,b,d){var c=i[o];var h=i[r];var f=a(e,t,o,r,g,b,d);u[c+6]+=f;u[h+6]+=f;l[s]=c;l[s+1]=h;l[s+2]=f;s+=n}));return{nodes:u,edges:l}};
/**
 * Function applying the layout back to the graph.
 *
 * @param {Graph}         graph         - Target graph.
 * @param {Float32Array}  NodeMatrix    - Node matrix.
 * @param {function|null} outputReducer - A node reducer.
 */e.assignLayoutChanges=function(e,n,a){var o=0;e.updateEachNodeAttributes((function(e,r){r.x=n[o];r.y=n[o+1];o+=t;return a?a(e,r):r}))};
/**
 * Function reading the positions (only) from the graph, to write them in the matrix.
 *
 * @param {Graph}        graph      - Target graph.
 * @param {Float32Array} NodeMatrix - Node matrix.
 */e.readGraphPositions=function(e,n){var a=0;e.forEachNode((function(e,o){n[a]=o.x;n[a+1]=o.y;a+=t}))};
/**
 * Function collecting the layout positions.
 *
 * @param  {Graph}         graph         - Target graph.
 * @param  {Float32Array}  NodeMatrix    - Node matrix.
 * @param  {function|null} outputReducer - A nodes reducer.
 * @return {object}                      - Map to node positions.
 */e.collectLayoutChanges=function(e,n,a){var o=e.nodes(),r={};for(var i=0,s=0,u=n.length;i<u;i+=t){if(a){var l=Object.assign({},e.getNodeAttributes(o[s]));l.x=n[i];l.y=n[i+1];l=a(o[s],l);r[o[s]]={x:l.x,y:l.y}}else r[o[s]]={x:n[i],y:n[i+1]};s++}return r};
/**
 * Function returning a web worker from the given function.
 *
 * @param  {function}  fn - Function for the worker.
 * @return {DOMString}
 */e.createWorker=function createWorker(e){var t=window.URL||window.webkitURL;var n=e.toString();var a=t.createObjectURL(new Blob(["("+n+").call(this);"],{type:"text/javascript"}));var o=new Worker(a);t.revokeObjectURL(a);return o};var a={};a={linLogMode:false,outboundAttractionDistribution:false,adjustSizes:false,edgeWeightInfluence:1,scalingRatio:1,strongGravityMode:false,gravity:1,slowDown:1,barnesHutOptimize:false,barnesHutTheta:.5};var o=a;export{o as _,e};

//# sourceMappingURL=987d9be9.js.map