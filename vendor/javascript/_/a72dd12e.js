var e={};var r=3;
/**
 * Function used to validate the given settings.
 *
 * @param  {object}      settings - Settings to validate.
 * @return {object|null}
 */e.validateSettings=function(e){return"gridSize"in e&&"number"!==typeof e.gridSize||e.gridSize<=0?{message:"the `gridSize` setting should be a positive number."}:"margin"in e&&"number"!==typeof e.margin||e.margin<0?{message:"the `margin` setting should be 0 or a positive number."}:"expansion"in e&&"number"!==typeof e.expansion||e.expansion<=0?{message:"the `expansion` setting should be a positive number."}:"ratio"in e&&"number"!==typeof e.ratio||e.ratio<=0?{message:"the `ratio` setting should be a positive number."}:"speed"in e&&"number"!==typeof e.speed||e.speed<=0?{message:"the `speed` setting should be a positive number."}:null};
/**
 * Function generating a flat matrix for the given graph's nodes.
 *
 * @param  {Graph}        graph   - Target graph.
 * @param  {function}     reducer - Node reducer function.
 * @return {Float32Array}         - The node matrix.
 */e.graphToByteArray=function(e,t){var n=e.order;var i=new Float32Array(n*r);var a=0;e.forEachNode((function(e,n){"function"===typeof t&&(n=t(e,n));i[a]=n.x;i[a+1]=n.y;i[a+2]=n.size||1;a+=r}));return i};
/**
 * Function applying the layout back to the graph.
 *
 * @param {Graph}        graph      - Target graph.
 * @param {Float32Array} NodeMatrix - Node matrix.
 * @param {function}     reducer    - Reducing function.
 */e.assignLayoutChanges=function(e,t,n){var i=0;e.forEachNode((function(a){var o={x:t[i],y:t[i+1]};"function"===typeof n&&(o=n(a,o));e.mergeNodeAttributes(a,o);i+=r}))};
/**
 * Function collecting the layout positions.
 *
 * @param  {Graph}        graph      - Target graph.
 * @param  {Float32Array} NodeMatrix - Node matrix.
 * @param  {function}     reducer    - Reducing function.
 * @return {object}                  - Map to node positions.
 */e.collectLayoutChanges=function(e,t,n){var i={};var a=0;e.forEachNode((function(e){var o={x:t[a],y:t[a+1]};"function"===typeof n&&(o=n(e,o));i[e]=o;a+=r}));return i};
/**
 * Function returning a web worker from the given function.
 *
 * @param  {function}  fn - Function for the worker.
 * @return {DOMString}
 */e.createWorker=function createWorker(e){var r=window.URL||window.webkitURL;var t=e.toString();var n=r.createObjectURL(new Blob(["("+t+").call(this);"],{type:"text/javascript"}));var i=new Worker(n);r.revokeObjectURL(n);return i};var t={};t={gridSize:20,margin:5,expansion:1.1,ratio:1,speed:3};var n=t;export{n as _,e};

//# sourceMappingURL=a72dd12e.js.map