// graphology@0.26.0 downloaded from https://ga.jspm.io/npm:graphology@0.26.0/dist/graphology.mjs

import{EventEmitter as e}from"events";
/**
 * Object.assign-like polyfill.
 *
 * @param  {object} target       - First object.
 * @param  {object} [...objects] - Objects to merge.
 * @return {object}
 */function assignPolyfill(){const e=arguments[0];for(let t=1,r=arguments.length;t<r;t++)if(arguments[t])for(const r in arguments[t])e[r]=arguments[t][r];return e}let t=assignPolyfill;typeof Object.assign==="function"&&(t=Object.assign)
/**
 * Function returning the first matching edge for given path.
 * Note: this function does not check the existence of source & target. This
 * must be performed by the caller.
 *
 * @param  {Graph}  graph  - Target graph.
 * @param  {any}    source - Source node.
 * @param  {any}    target - Target node.
 * @param  {string} type   - Type of the edge (mixed, directed or undirected).
 * @return {string|null}
 */;function getMatchingEdge(e,t,r,i){const n=e._nodes.get(t);let o=null;if(!n)return o;o=i==="mixed"?n.out&&n.out[r]||n.undirected&&n.undirected[r]:i==="directed"?n.out&&n.out[r]:n.undirected&&n.undirected[r];return o}
/**
 * Checks whether the given value is a plain object.
 *
 * @param  {mixed}   value - Target value.
 * @return {boolean}
 */function isPlainObject(e){return typeof e==="object"&&e!==null}
/**
 * Checks whether the given object is empty.
 *
 * @param  {object}  o - Target Object.
 * @return {boolean}
 */function isEmpty(e){let t;for(t in e)return false;return true}
/**
 * Creates a "private" property for the given member name by concealing it
 * using the `enumerable` option.
 *
 * @param {object} target - Target object.
 * @param {string} name   - Member name.
 */function privateProperty(e,t,r){Object.defineProperty(e,t,{enumerable:false,configurable:false,writable:true,value:r})}
/**
 * Creates a read-only property for the given member name & the given getter.
 *
 * @param {object}   target - Target object.
 * @param {string}   name   - Member name.
 * @param {mixed}    value  - The attached getter or fixed value.
 */function readOnlyProperty(e,t,r){const i={enumerable:true,configurable:true};if(typeof r==="function")i.get=r;else{i.value=r;i.writable=false}Object.defineProperty(e,t,i)}
/**
 * Returns whether the given object constitute valid hints.
 *
 * @param {object} hints - Target object.
 */function validateHints(e){return!!isPlainObject(e)&&!(e.attributes&&!Array.isArray(e.attributes))}function incrementalIdStartingFromRandomByte(){let e=Math.floor(Math.random()*256)&255;return()=>e++}
/**
 * Chains multiple iterators into a single iterator.
 *
 * @param {...Iterator} iterables
 * @returns {Iterator}
 */function chain(){const e=arguments;let t=null;let r=-1;return{[Symbol.iterator](){return this},next(){let i=null;do{if(t===null){r++;if(r>=e.length)return{done:true};t=e[r][Symbol.iterator]()}i=t.next();if(!i.done)break;t=null}while(true);return i}}}function emptyIterator(){return{[Symbol.iterator](){return this},next(){return{done:true}}}}class GraphError extends Error{constructor(e){super();this.name="GraphError";this.message=e}}class InvalidArgumentsGraphError extends GraphError{constructor(e){super(e);this.name="InvalidArgumentsGraphError";typeof Error.captureStackTrace==="function"&&Error.captureStackTrace(this,InvalidArgumentsGraphError.prototype.constructor)}}class NotFoundGraphError extends GraphError{constructor(e){super(e);this.name="NotFoundGraphError";typeof Error.captureStackTrace==="function"&&Error.captureStackTrace(this,NotFoundGraphError.prototype.constructor)}}class UsageGraphError extends GraphError{constructor(e){super(e);this.name="UsageGraphError";typeof Error.captureStackTrace==="function"&&Error.captureStackTrace(this,UsageGraphError.prototype.constructor)}}
/**
 * MixedNodeData class.
 *
 * @constructor
 * @param {string} string     - The node's key.
 * @param {object} attributes - Node's attributes.
 */function MixedNodeData(e,t){this.key=e;this.attributes=t;this.clear()}MixedNodeData.prototype.clear=function(){this.inDegree=0;this.outDegree=0;this.undirectedDegree=0;this.undirectedLoops=0;this.directedLoops=0;this.in={};this.out={};this.undirected={}};
/**
 * DirectedNodeData class.
 *
 * @constructor
 * @param {string} string     - The node's key.
 * @param {object} attributes - Node's attributes.
 */function DirectedNodeData(e,t){this.key=e;this.attributes=t;this.clear()}DirectedNodeData.prototype.clear=function(){this.inDegree=0;this.outDegree=0;this.directedLoops=0;this.in={};this.out={}};
/**
 * UndirectedNodeData class.
 *
 * @constructor
 * @param {string} string     - The node's key.
 * @param {object} attributes - Node's attributes.
 */function UndirectedNodeData(e,t){this.key=e;this.attributes=t;this.clear()}UndirectedNodeData.prototype.clear=function(){this.undirectedDegree=0;this.undirectedLoops=0;this.undirected={}};
/**
 * EdgeData class.
 *
 * @constructor
 * @param {boolean} undirected   - Whether the edge is undirected.
 * @param {string}  string       - The edge's key.
 * @param {string}  source       - Source of the edge.
 * @param {string}  target       - Target of the edge.
 * @param {object}  attributes   - Edge's attributes.
 */function EdgeData(e,t,r,i,n){this.key=t;this.attributes=n;this.undirected=e;this.source=r;this.target=i}EdgeData.prototype.attach=function(){let e="out";let t="in";this.undirected&&(e=t="undirected");const r=this.source.key;const i=this.target.key;this.source[e][i]=this;this.undirected&&r===i||(this.target[t][r]=this)};EdgeData.prototype.attachMulti=function(){let e="out";let t="in";const r=this.source.key;const i=this.target.key;this.undirected&&(e=t="undirected");const n=this.source[e];const o=n[i];if(typeof o!=="undefined"){o.previous=this;this.next=o;n[i]=this;this.target[t][r]=this}else{n[i]=this;this.undirected&&r===i||(this.target[t][r]=this)}};EdgeData.prototype.detach=function(){const e=this.source.key;const t=this.target.key;let r="out";let i="in";this.undirected&&(r=i="undirected");delete this.source[r][t];delete this.target[i][e]};EdgeData.prototype.detachMulti=function(){const e=this.source.key;const t=this.target.key;let r="out";let i="in";this.undirected&&(r=i="undirected");if(this.previous===void 0)if(this.next===void 0){delete this.source[r][t];delete this.target[i][e]}else{this.next.previous=void 0;this.source[r][t]=this.next;this.target[i][e]=this.next}else{this.previous.next=this.next;this.next!==void 0&&(this.next.previous=this.previous)}};const r=0;const i=1;const n=2;const o=3;function findRelevantNodeData(e,t,n,a,d,s,h){let u,c,p,l;a=""+a;if(n===r){u=e._nodes.get(a);if(!u)throw new NotFoundGraphError(`Graph.${t}: could not find the "${a}" node in the graph.`);p=d;l=s}else if(n===o){d=""+d;c=e._edges.get(d);if(!c)throw new NotFoundGraphError(`Graph.${t}: could not find the "${d}" edge in the graph.`);const r=c.source.key;const i=c.target.key;if(a===r)u=c.target;else{if(a!==i)throw new NotFoundGraphError(`Graph.${t}: the "${a}" node is not attached to the "${d}" edge (${r}, ${i}).`);u=c.source}p=s;l=h}else{c=e._edges.get(a);if(!c)throw new NotFoundGraphError(`Graph.${t}: could not find the "${a}" edge in the graph.`);u=n===i?c.source:c.target;p=d;l=s}return[u,p,l]}function attachNodeAttributeGetter(e,t,r){e.prototype[t]=function(e,i,n){const[o,a]=findRelevantNodeData(this,t,r,e,i,n);return o.attributes[a]}}function attachNodeAttributesGetter(e,t,r){e.prototype[t]=function(e,i){const[n]=findRelevantNodeData(this,t,r,e,i);return n.attributes}}function attachNodeAttributeChecker(e,t,r){e.prototype[t]=function(e,i,n){const[o,a]=findRelevantNodeData(this,t,r,e,i,n);return o.attributes.hasOwnProperty(a)}}function attachNodeAttributeSetter(e,t,r){e.prototype[t]=function(e,i,n,o){const[a,d,s]=findRelevantNodeData(this,t,r,e,i,n,o);a.attributes[d]=s;this.emit("nodeAttributesUpdated",{key:a.key,type:"set",attributes:a.attributes,name:d});return this}}function attachNodeAttributeUpdater(e,t,r){e.prototype[t]=function(e,i,n,o){const[a,d,s]=findRelevantNodeData(this,t,r,e,i,n,o);if(typeof s!=="function")throw new InvalidArgumentsGraphError(`Graph.${t}: updater should be a function.`);const h=a.attributes;const u=s(h[d]);h[d]=u;this.emit("nodeAttributesUpdated",{key:a.key,type:"set",attributes:a.attributes,name:d});return this}}function attachNodeAttributeRemover(e,t,r){e.prototype[t]=function(e,i,n){const[o,a]=findRelevantNodeData(this,t,r,e,i,n);delete o.attributes[a];this.emit("nodeAttributesUpdated",{key:o.key,type:"remove",attributes:o.attributes,name:a});return this}}function attachNodeAttributesReplacer(e,t,r){e.prototype[t]=function(e,i,n){const[o,a]=findRelevantNodeData(this,t,r,e,i,n);if(!isPlainObject(a))throw new InvalidArgumentsGraphError(`Graph.${t}: provided attributes are not a plain object.`);o.attributes=a;this.emit("nodeAttributesUpdated",{key:o.key,type:"replace",attributes:o.attributes});return this}}function attachNodeAttributesMerger(e,r,i){e.prototype[r]=function(e,n,o){const[a,d]=findRelevantNodeData(this,r,i,e,n,o);if(!isPlainObject(d))throw new InvalidArgumentsGraphError(`Graph.${r}: provided attributes are not a plain object.`);t(a.attributes,d);this.emit("nodeAttributesUpdated",{key:a.key,type:"merge",attributes:a.attributes,data:d});return this}}function attachNodeAttributesUpdater(e,t,r){e.prototype[t]=function(e,i,n){const[o,a]=findRelevantNodeData(this,t,r,e,i,n);if(typeof a!=="function")throw new InvalidArgumentsGraphError(`Graph.${t}: provided updater is not a function.`);o.attributes=a(o.attributes);this.emit("nodeAttributesUpdated",{key:o.key,type:"update",attributes:o.attributes});return this}}const a=[{name:e=>`get${e}Attribute`,attacher:attachNodeAttributeGetter},{name:e=>`get${e}Attributes`,attacher:attachNodeAttributesGetter},{name:e=>`has${e}Attribute`,attacher:attachNodeAttributeChecker},{name:e=>`set${e}Attribute`,attacher:attachNodeAttributeSetter},{name:e=>`update${e}Attribute`,attacher:attachNodeAttributeUpdater},{name:e=>`remove${e}Attribute`,attacher:attachNodeAttributeRemover},{name:e=>`replace${e}Attributes`,attacher:attachNodeAttributesReplacer},{name:e=>`merge${e}Attributes`,attacher:attachNodeAttributesMerger},{name:e=>`update${e}Attributes`,attacher:attachNodeAttributesUpdater}];
/**
 * Attach every attributes-related methods to a Graph class.
 *
 * @param {function} Graph - Target class.
 */function attachNodeAttributesMethods(e){a.forEach((function({name:t,attacher:a}){a(e,t("Node"),r);a(e,t("Source"),i);a(e,t("Target"),n);a(e,t("Opposite"),o)}))}
/**
 * Attach an attribute getter method onto the provided class.
 *
 * @param {function} Class         - Target class.
 * @param {string}   method        - Method name.
 * @param {string}   type          - Type of the edge to find.
 */function attachEdgeAttributeGetter(e,t,r){
/**
   * Get the desired attribute for the given element (node or edge).
   *
   * Arity 2:
   * @param  {any}    element - Target element.
   * @param  {string} name    - Attribute's name.
   *
   * Arity 3 (only for edges):
   * @param  {any}     source - Source element.
   * @param  {any}     target - Target element.
   * @param  {string}  name   - Attribute's name.
   *
   * @return {mixed}          - The attribute's value.
   *
   * @throws {Error} - Will throw if too many arguments are provided.
   * @throws {Error} - Will throw if any of the elements is not found.
   */
e.prototype[t]=function(e,i){let n;if(this.type!=="mixed"&&r!=="mixed"&&r!==this.type)throw new UsageGraphError(`Graph.${t}: cannot find this type of edges in your ${this.type} graph.`);if(arguments.length>2){if(this.multi)throw new UsageGraphError(`Graph.${t}: cannot use a {source,target} combo when asking about an edge's attributes in a MultiGraph since we cannot infer the one you want information about.`);const o=""+e;const a=""+i;i=arguments[2];n=getMatchingEdge(this,o,a,r);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find an edge for the given path ("${o}" - "${a}").`)}else{if(r!=="mixed")throw new UsageGraphError(`Graph.${t}: calling this method with only a key (vs. a source and target) does not make sense since an edge with this key could have the other type.`);e=""+e;n=this._edges.get(e);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find the "${e}" edge in the graph.`)}return n.attributes[i]}}
/**
 * Attach an attributes getter method onto the provided class.
 *
 * @param {function} Class       - Target class.
 * @param {string}   method      - Method name.
 * @param {string}   type        - Type of the edge to find.
 */function attachEdgeAttributesGetter(e,t,r){
/**
   * Retrieves all the target element's attributes.
   *
   * Arity 2:
   * @param  {any}    element - Target element.
   *
   * Arity 3 (only for edges):
   * @param  {any}     source - Source element.
   * @param  {any}     target - Target element.
   *
   * @return {object}          - The element's attributes.
   *
   * @throws {Error} - Will throw if too many arguments are provided.
   * @throws {Error} - Will throw if any of the elements is not found.
   */
e.prototype[t]=function(e){let i;if(this.type!=="mixed"&&r!=="mixed"&&r!==this.type)throw new UsageGraphError(`Graph.${t}: cannot find this type of edges in your ${this.type} graph.`);if(arguments.length>1){if(this.multi)throw new UsageGraphError(`Graph.${t}: cannot use a {source,target} combo when asking about an edge's attributes in a MultiGraph since we cannot infer the one you want information about.`);const n=""+e,o=""+arguments[1];i=getMatchingEdge(this,n,o,r);if(!i)throw new NotFoundGraphError(`Graph.${t}: could not find an edge for the given path ("${n}" - "${o}").`)}else{if(r!=="mixed")throw new UsageGraphError(`Graph.${t}: calling this method with only a key (vs. a source and target) does not make sense since an edge with this key could have the other type.`);e=""+e;i=this._edges.get(e);if(!i)throw new NotFoundGraphError(`Graph.${t}: could not find the "${e}" edge in the graph.`)}return i.attributes}}
/**
 * Attach an attribute checker method onto the provided class.
 *
 * @param {function} Class       - Target class.
 * @param {string}   method      - Method name.
 * @param {string}   type        - Type of the edge to find.
 */function attachEdgeAttributeChecker(e,t,r){
/**
   * Checks whether the desired attribute is set for the given element (node or edge).
   *
   * Arity 2:
   * @param  {any}    element - Target element.
   * @param  {string} name    - Attribute's name.
   *
   * Arity 3 (only for edges):
   * @param  {any}     source - Source element.
   * @param  {any}     target - Target element.
   * @param  {string}  name   - Attribute's name.
   *
   * @return {boolean}
   *
   * @throws {Error} - Will throw if too many arguments are provided.
   * @throws {Error} - Will throw if any of the elements is not found.
   */
e.prototype[t]=function(e,i){let n;if(this.type!=="mixed"&&r!=="mixed"&&r!==this.type)throw new UsageGraphError(`Graph.${t}: cannot find this type of edges in your ${this.type} graph.`);if(arguments.length>2){if(this.multi)throw new UsageGraphError(`Graph.${t}: cannot use a {source,target} combo when asking about an edge's attributes in a MultiGraph since we cannot infer the one you want information about.`);const o=""+e;const a=""+i;i=arguments[2];n=getMatchingEdge(this,o,a,r);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find an edge for the given path ("${o}" - "${a}").`)}else{if(r!=="mixed")throw new UsageGraphError(`Graph.${t}: calling this method with only a key (vs. a source and target) does not make sense since an edge with this key could have the other type.`);e=""+e;n=this._edges.get(e);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find the "${e}" edge in the graph.`)}return n.attributes.hasOwnProperty(i)}}
/**
 * Attach an attribute setter method onto the provided class.
 *
 * @param {function} Class         - Target class.
 * @param {string}   method        - Method name.
 * @param {string}   type          - Type of the edge to find.
 */function attachEdgeAttributeSetter(e,t,r){
/**
   * Set the desired attribute for the given element (node or edge).
   *
   * Arity 2:
   * @param  {any}    element - Target element.
   * @param  {string} name    - Attribute's name.
   * @param  {mixed}  value   - New attribute value.
   *
   * Arity 3 (only for edges):
   * @param  {any}     source - Source element.
   * @param  {any}     target - Target element.
   * @param  {string}  name   - Attribute's name.
   * @param  {mixed}  value   - New attribute value.
   *
   * @return {Graph}          - Returns itself for chaining.
   *
   * @throws {Error} - Will throw if too many arguments are provided.
   * @throws {Error} - Will throw if any of the elements is not found.
   */
e.prototype[t]=function(e,i,n){let o;if(this.type!=="mixed"&&r!=="mixed"&&r!==this.type)throw new UsageGraphError(`Graph.${t}: cannot find this type of edges in your ${this.type} graph.`);if(arguments.length>3){if(this.multi)throw new UsageGraphError(`Graph.${t}: cannot use a {source,target} combo when asking about an edge's attributes in a MultiGraph since we cannot infer the one you want information about.`);const a=""+e;const d=""+i;i=arguments[2];n=arguments[3];o=getMatchingEdge(this,a,d,r);if(!o)throw new NotFoundGraphError(`Graph.${t}: could not find an edge for the given path ("${a}" - "${d}").`)}else{if(r!=="mixed")throw new UsageGraphError(`Graph.${t}: calling this method with only a key (vs. a source and target) does not make sense since an edge with this key could have the other type.`);e=""+e;o=this._edges.get(e);if(!o)throw new NotFoundGraphError(`Graph.${t}: could not find the "${e}" edge in the graph.`)}o.attributes[i]=n;this.emit("edgeAttributesUpdated",{key:o.key,type:"set",attributes:o.attributes,name:i});return this}}
/**
 * Attach an attribute updater method onto the provided class.
 *
 * @param {function} Class         - Target class.
 * @param {string}   method        - Method name.
 * @param {string}   type          - Type of the edge to find.
 */function attachEdgeAttributeUpdater(e,t,r){
/**
   * Update the desired attribute for the given element (node or edge) using
   * the provided function.
   *
   * Arity 2:
   * @param  {any}      element - Target element.
   * @param  {string}   name    - Attribute's name.
   * @param  {function} updater - Updater function.
   *
   * Arity 3 (only for edges):
   * @param  {any}      source  - Source element.
   * @param  {any}      target  - Target element.
   * @param  {string}   name    - Attribute's name.
   * @param  {function} updater - Updater function.
   *
   * @return {Graph}            - Returns itself for chaining.
   *
   * @throws {Error} - Will throw if too many arguments are provided.
   * @throws {Error} - Will throw if any of the elements is not found.
   */
e.prototype[t]=function(e,i,n){let o;if(this.type!=="mixed"&&r!=="mixed"&&r!==this.type)throw new UsageGraphError(`Graph.${t}: cannot find this type of edges in your ${this.type} graph.`);if(arguments.length>3){if(this.multi)throw new UsageGraphError(`Graph.${t}: cannot use a {source,target} combo when asking about an edge's attributes in a MultiGraph since we cannot infer the one you want information about.`);const a=""+e;const d=""+i;i=arguments[2];n=arguments[3];o=getMatchingEdge(this,a,d,r);if(!o)throw new NotFoundGraphError(`Graph.${t}: could not find an edge for the given path ("${a}" - "${d}").`)}else{if(r!=="mixed")throw new UsageGraphError(`Graph.${t}: calling this method with only a key (vs. a source and target) does not make sense since an edge with this key could have the other type.`);e=""+e;o=this._edges.get(e);if(!o)throw new NotFoundGraphError(`Graph.${t}: could not find the "${e}" edge in the graph.`)}if(typeof n!=="function")throw new InvalidArgumentsGraphError(`Graph.${t}: updater should be a function.`);o.attributes[i]=n(o.attributes[i]);this.emit("edgeAttributesUpdated",{key:o.key,type:"set",attributes:o.attributes,name:i});return this}}
/**
 * Attach an attribute remover method onto the provided class.
 *
 * @param {function} Class         - Target class.
 * @param {string}   method        - Method name.
 * @param {string}   type          - Type of the edge to find.
 */function attachEdgeAttributeRemover(e,t,r){
/**
   * Remove the desired attribute for the given element (node or edge).
   *
   * Arity 2:
   * @param  {any}    element - Target element.
   * @param  {string} name    - Attribute's name.
   *
   * Arity 3 (only for edges):
   * @param  {any}     source - Source element.
   * @param  {any}     target - Target element.
   * @param  {string}  name   - Attribute's name.
   *
   * @return {Graph}          - Returns itself for chaining.
   *
   * @throws {Error} - Will throw if too many arguments are provided.
   * @throws {Error} - Will throw if any of the elements is not found.
   */
e.prototype[t]=function(e,i){let n;if(this.type!=="mixed"&&r!=="mixed"&&r!==this.type)throw new UsageGraphError(`Graph.${t}: cannot find this type of edges in your ${this.type} graph.`);if(arguments.length>2){if(this.multi)throw new UsageGraphError(`Graph.${t}: cannot use a {source,target} combo when asking about an edge's attributes in a MultiGraph since we cannot infer the one you want information about.`);const o=""+e;const a=""+i;i=arguments[2];n=getMatchingEdge(this,o,a,r);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find an edge for the given path ("${o}" - "${a}").`)}else{if(r!=="mixed")throw new UsageGraphError(`Graph.${t}: calling this method with only a key (vs. a source and target) does not make sense since an edge with this key could have the other type.`);e=""+e;n=this._edges.get(e);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find the "${e}" edge in the graph.`)}delete n.attributes[i];this.emit("edgeAttributesUpdated",{key:n.key,type:"remove",attributes:n.attributes,name:i});return this}}
/**
 * Attach an attribute replacer method onto the provided class.
 *
 * @param {function} Class         - Target class.
 * @param {string}   method        - Method name.
 * @param {string}   type          - Type of the edge to find.
 */function attachEdgeAttributesReplacer(e,t,r){
/**
   * Replace the attributes for the given element (node or edge).
   *
   * Arity 2:
   * @param  {any}    element    - Target element.
   * @param  {object} attributes - New attributes.
   *
   * Arity 3 (only for edges):
   * @param  {any}     source     - Source element.
   * @param  {any}     target     - Target element.
   * @param  {object}  attributes - New attributes.
   *
   * @return {Graph}              - Returns itself for chaining.
   *
   * @throws {Error} - Will throw if too many arguments are provided.
   * @throws {Error} - Will throw if any of the elements is not found.
   */
e.prototype[t]=function(e,i){let n;if(this.type!=="mixed"&&r!=="mixed"&&r!==this.type)throw new UsageGraphError(`Graph.${t}: cannot find this type of edges in your ${this.type} graph.`);if(arguments.length>2){if(this.multi)throw new UsageGraphError(`Graph.${t}: cannot use a {source,target} combo when asking about an edge's attributes in a MultiGraph since we cannot infer the one you want information about.`);const o=""+e,a=""+i;i=arguments[2];n=getMatchingEdge(this,o,a,r);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find an edge for the given path ("${o}" - "${a}").`)}else{if(r!=="mixed")throw new UsageGraphError(`Graph.${t}: calling this method with only a key (vs. a source and target) does not make sense since an edge with this key could have the other type.`);e=""+e;n=this._edges.get(e);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find the "${e}" edge in the graph.`)}if(!isPlainObject(i))throw new InvalidArgumentsGraphError(`Graph.${t}: provided attributes are not a plain object.`);n.attributes=i;this.emit("edgeAttributesUpdated",{key:n.key,type:"replace",attributes:n.attributes});return this}}
/**
 * Attach an attribute merger method onto the provided class.
 *
 * @param {function} Class         - Target class.
 * @param {string}   method        - Method name.
 * @param {string}   type          - Type of the edge to find.
 */function attachEdgeAttributesMerger(e,r,i){
/**
   * Merge the attributes for the given element (node or edge).
   *
   * Arity 2:
   * @param  {any}    element    - Target element.
   * @param  {object} attributes - Attributes to merge.
   *
   * Arity 3 (only for edges):
   * @param  {any}     source     - Source element.
   * @param  {any}     target     - Target element.
   * @param  {object}  attributes - Attributes to merge.
   *
   * @return {Graph}              - Returns itself for chaining.
   *
   * @throws {Error} - Will throw if too many arguments are provided.
   * @throws {Error} - Will throw if any of the elements is not found.
   */
e.prototype[r]=function(e,n){let o;if(this.type!=="mixed"&&i!=="mixed"&&i!==this.type)throw new UsageGraphError(`Graph.${r}: cannot find this type of edges in your ${this.type} graph.`);if(arguments.length>2){if(this.multi)throw new UsageGraphError(`Graph.${r}: cannot use a {source,target} combo when asking about an edge's attributes in a MultiGraph since we cannot infer the one you want information about.`);const t=""+e,a=""+n;n=arguments[2];o=getMatchingEdge(this,t,a,i);if(!o)throw new NotFoundGraphError(`Graph.${r}: could not find an edge for the given path ("${t}" - "${a}").`)}else{if(i!=="mixed")throw new UsageGraphError(`Graph.${r}: calling this method with only a key (vs. a source and target) does not make sense since an edge with this key could have the other type.`);e=""+e;o=this._edges.get(e);if(!o)throw new NotFoundGraphError(`Graph.${r}: could not find the "${e}" edge in the graph.`)}if(!isPlainObject(n))throw new InvalidArgumentsGraphError(`Graph.${r}: provided attributes are not a plain object.`);t(o.attributes,n);this.emit("edgeAttributesUpdated",{key:o.key,type:"merge",attributes:o.attributes,data:n});return this}}
/**
 * Attach an attribute updater method onto the provided class.
 *
 * @param {function} Class         - Target class.
 * @param {string}   method        - Method name.
 * @param {string}   type          - Type of the edge to find.
 */function attachEdgeAttributesUpdater(e,t,r){
/**
   * Update the attributes of the given element (node or edge).
   *
   * Arity 2:
   * @param  {any}      element - Target element.
   * @param  {function} updater - Updater function.
   *
   * Arity 3 (only for edges):
   * @param  {any}      source  - Source element.
   * @param  {any}      target  - Target element.
   * @param  {function} updater - Updater function.
   *
   * @return {Graph}            - Returns itself for chaining.
   *
   * @throws {Error} - Will throw if too many arguments are provided.
   * @throws {Error} - Will throw if any of the elements is not found.
   */
e.prototype[t]=function(e,i){let n;if(this.type!=="mixed"&&r!=="mixed"&&r!==this.type)throw new UsageGraphError(`Graph.${t}: cannot find this type of edges in your ${this.type} graph.`);if(arguments.length>2){if(this.multi)throw new UsageGraphError(`Graph.${t}: cannot use a {source,target} combo when asking about an edge's attributes in a MultiGraph since we cannot infer the one you want information about.`);const o=""+e,a=""+i;i=arguments[2];n=getMatchingEdge(this,o,a,r);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find an edge for the given path ("${o}" - "${a}").`)}else{if(r!=="mixed")throw new UsageGraphError(`Graph.${t}: calling this method with only a key (vs. a source and target) does not make sense since an edge with this key could have the other type.`);e=""+e;n=this._edges.get(e);if(!n)throw new NotFoundGraphError(`Graph.${t}: could not find the "${e}" edge in the graph.`)}if(typeof i!=="function")throw new InvalidArgumentsGraphError(`Graph.${t}: provided updater is not a function.`);n.attributes=i(n.attributes);this.emit("edgeAttributesUpdated",{key:n.key,type:"update",attributes:n.attributes});return this}}const d=[{name:e=>`get${e}Attribute`,attacher:attachEdgeAttributeGetter},{name:e=>`get${e}Attributes`,attacher:attachEdgeAttributesGetter},{name:e=>`has${e}Attribute`,attacher:attachEdgeAttributeChecker},{name:e=>`set${e}Attribute`,attacher:attachEdgeAttributeSetter},{name:e=>`update${e}Attribute`,attacher:attachEdgeAttributeUpdater},{name:e=>`remove${e}Attribute`,attacher:attachEdgeAttributeRemover},{name:e=>`replace${e}Attributes`,attacher:attachEdgeAttributesReplacer},{name:e=>`merge${e}Attributes`,attacher:attachEdgeAttributesMerger},{name:e=>`update${e}Attributes`,attacher:attachEdgeAttributesUpdater}];
/**
 * Attach every attributes-related methods to a Graph class.
 *
 * @param {function} Graph - Target class.
 */function attachEdgeAttributesMethods(e){d.forEach((function({name:t,attacher:r}){r(e,t("Edge"),"mixed");r(e,t("DirectedEdge"),"directed");r(e,t("UndirectedEdge"),"undirected")}))}const s=[{name:"edges",type:"mixed"},{name:"inEdges",type:"directed",direction:"in"},{name:"outEdges",type:"directed",direction:"out"},{name:"inboundEdges",type:"mixed",direction:"in"},{name:"outboundEdges",type:"mixed",direction:"out"},{name:"directedEdges",type:"directed"},{name:"undirectedEdges",type:"undirected"}];
/**
 * Function iterating over edges from the given object to match one of them.
 *
 * @param {object}   object   - Target object.
 * @param {function} callback - Function to call.
 */function forEachSimple(e,t,r,i){let n=false;for(const o in t){if(o===i)continue;const a=t[o];n=r(a.key,a.attributes,a.source.key,a.target.key,a.source.attributes,a.target.attributes,a.undirected);if(e&&n)return a.key}}function forEachMulti(e,t,r,i){let n,o,a;let d=false;for(const s in t)if(s!==i){n=t[s];do{o=n.source;a=n.target;d=r(n.key,n.attributes,o.key,a.key,o.attributes,a.attributes,n.undirected);if(e&&d)return n.key;n=n.next}while(n!==void 0)}}
/**
 * Function returning an iterator over edges from the given object.
 *
 * @param  {object}   object - Target object.
 * @return {Iterator}
 */function createIterator(e,t){const r=Object.keys(e);const i=r.length;let n;let o=0;return{[Symbol.iterator](){return this},next(){do{if(n)n=n.next;else{if(o>=i)return{done:true};const a=r[o++];if(a===t){n=void 0;continue}n=e[a]}}while(!n);return{done:false,value:{edge:n.key,attributes:n.attributes,source:n.source.key,target:n.target.key,sourceAttributes:n.source.attributes,targetAttributes:n.target.attributes,undirected:n.undirected}}}}}
/**
 * Function iterating over the egdes from the object at given key to match
 * one of them.
 *
 * @param {object}   object   - Target object.
 * @param {mixed}    k        - Neighbor key.
 * @param {function} callback - Callback to use.
 */function forEachForKeySimple(e,t,r,i){const n=t[r];if(!n)return;const o=n.source;const a=n.target;return i(n.key,n.attributes,o.key,a.key,o.attributes,a.attributes,n.undirected)&&e?n.key:void 0}function forEachForKeyMulti(e,t,r,i){let n=t[r];if(!n)return;let o=false;do{o=i(n.key,n.attributes,n.source.key,n.target.key,n.source.attributes,n.target.attributes,n.undirected);if(e&&o)return n.key;n=n.next}while(n!==void 0)}
/**
 * Function returning an iterator over the egdes from the object at given key.
 *
 * @param  {object}   object   - Target object.
 * @param  {mixed}    k        - Neighbor key.
 * @return {Iterator}
 */function createIteratorForKey(e,t){let r=e[t];if(r.next!==void 0)return{[Symbol.iterator](){return this},next(){if(!r)return{done:true};const e={edge:r.key,attributes:r.attributes,source:r.source.key,target:r.target.key,sourceAttributes:r.source.attributes,targetAttributes:r.target.attributes,undirected:r.undirected};r=r.next;return{done:false,value:e}}};let i=false;return{[Symbol.iterator](){return this},next(){if(i===true)return{done:true};i=true;return{done:false,value:{edge:r.key,attributes:r.attributes,source:r.source.key,target:r.target.key,sourceAttributes:r.source.attributes,targetAttributes:r.target.attributes,undirected:r.undirected}}}}}
/**
 * Function creating an array of edges for the given type.
 *
 * @param  {Graph}   graph - Target Graph instance.
 * @param  {string}  type  - Type of edges to retrieve.
 * @return {array}         - Array of edges.
 */function createEdgeArray(e,t){if(e.size===0)return[];if(t==="mixed"||t===e.type)return Array.from(e._edges.keys());const r=t==="undirected"?e.undirectedSize:e.directedSize;const i=new Array(r),n=t==="undirected";const o=e._edges.values();let a=0;let d,s;while(d=o.next(),d.done!==true){s=d.value;s.undirected===n&&(i[a++]=s.key)}return i}
/**
 * Function iterating over a graph's edges using a callback to match one of
 * them.
 *
 * @param  {Graph}    graph    - Target Graph instance.
 * @param  {string}   type     - Type of edges to retrieve.
 * @param  {function} callback - Function to call.
 */function forEachEdge(e,t,r,i){if(t.size===0)return;const n=r!=="mixed"&&r!==t.type;const o=r==="undirected";let a,d;let s=false;const h=t._edges.values();while(a=h.next(),a.done!==true){d=a.value;if(n&&d.undirected!==o)continue;const{key:t,attributes:r,source:h,target:u}=d;s=i(t,r,h.key,u.key,h.attributes,u.attributes,d.undirected);if(e&&s)return t}}
/**
 * Function creating an iterator of edges for the given type.
 *
 * @param  {Graph}    graph - Target Graph instance.
 * @param  {string}   type  - Type of edges to retrieve.
 * @return {Iterator}
 */function createEdgeIterator(e,t){if(e.size===0)return emptyIterator();const r=t!=="mixed"&&t!==e.type;const i=t==="undirected";const n=e._edges.values();return{[Symbol.iterator](){return this},next(){let e,t;while(true){e=n.next();if(e.done)return e;t=e.value;if(!r||t.undirected===i)break}const o={edge:t.key,attributes:t.attributes,source:t.source.key,target:t.target.key,sourceAttributes:t.source.attributes,targetAttributes:t.target.attributes,undirected:t.undirected};return{value:o,done:false}}}}
/**
 * Function iterating over a node's edges using a callback to match one of them.
 *
 * @param  {boolean}  multi     - Whether the graph is multi or not.
 * @param  {string}   type      - Type of edges to retrieve.
 * @param  {string}   direction - In or out?
 * @param  {any}      nodeData  - Target node's data.
 * @param  {function} callback  - Function to call.
 */function forEachEdgeForNode(e,t,r,i,n,o){const a=t?forEachMulti:forEachSimple;let d;if(r!=="undirected"){if(i!=="out"){d=a(e,n.in,o);if(e&&d)return d}if(i!=="in"){d=a(e,n.out,o,i?void 0:n.key);if(e&&d)return d}}if(r!=="directed"){d=a(e,n.undirected,o);if(e&&d)return d}}
/**
 * Function creating an array of edges for the given type & the given node.
 *
 * @param  {boolean} multi     - Whether the graph is multi or not.
 * @param  {string}  type      - Type of edges to retrieve.
 * @param  {string}  direction - In or out?
 * @param  {any}     nodeData  - Target node's data.
 * @return {array}             - Array of edges.
 */function createEdgeArrayForNode(e,t,r,i){const n=[];forEachEdgeForNode(false,e,t,r,i,(function(e){n.push(e)}));return n}
/**
 * Function iterating over a node's edges using a callback.
 *
 * @param  {string}   type      - Type of edges to retrieve.
 * @param  {string}   direction - In or out?
 * @param  {any}      nodeData  - Target node's data.
 * @return {Iterator}
 */function createEdgeIteratorForNode(e,t,r){let i=emptyIterator();if(e!=="undirected"){t!=="out"&&typeof r.in!=="undefined"&&(i=chain(i,createIterator(r.in)));t!=="in"&&typeof r.out!=="undefined"&&(i=chain(i,createIterator(r.out,t?void 0:r.key)))}e!=="directed"&&typeof r.undirected!=="undefined"&&(i=chain(i,createIterator(r.undirected)));return i}
/**
 * Function iterating over edges for the given path using a callback to match
 * one of them.
 *
 * @param  {string}   type       - Type of edges to retrieve.
 * @param  {boolean}  multi      - Whether the graph is multi.
 * @param  {string}   direction  - In or out?
 * @param  {NodeData} sourceData - Source node's data.
 * @param  {string}   target     - Target node.
 * @param  {function} callback   - Function to call.
 */function forEachEdgeForPath(e,t,r,i,n,o,a){const d=r?forEachForKeyMulti:forEachForKeySimple;let s;if(t!=="undirected"){if(typeof n.in!=="undefined"&&i!=="out"){s=d(e,n.in,o,a);if(e&&s)return s}if(typeof n.out!=="undefined"&&i!=="in"&&(i||n.key!==o)){s=d(e,n.out,o,a);if(e&&s)return s}}if(t!=="directed"&&typeof n.undirected!=="undefined"){s=d(e,n.undirected,o,a);if(e&&s)return s}}
/**
 * Function creating an array of edges for the given path.
 *
 * @param  {string}   type       - Type of edges to retrieve.
 * @param  {boolean}  multi      - Whether the graph is multi.
 * @param  {string}   direction  - In or out?
 * @param  {NodeData} sourceData - Source node's data.
 * @param  {any}      target     - Target node.
 * @return {array}               - Array of edges.
 */function createEdgeArrayForPath(e,t,r,i,n){const o=[];forEachEdgeForPath(false,e,t,r,i,n,(function(e){o.push(e)}));return o}
/**
 * Function returning an iterator over edges for the given path.
 *
 * @param  {string}   type       - Type of edges to retrieve.
 * @param  {string}   direction  - In or out?
 * @param  {NodeData} sourceData - Source node's data.
 * @param  {string}   target     - Target node.
 * @param  {function} callback   - Function to call.
 */function createEdgeIteratorForPath(e,t,r,i){let n=emptyIterator();if(e!=="undirected"){typeof r.in!=="undefined"&&t!=="out"&&i in r.in&&(n=chain(n,createIteratorForKey(r.in,i)));typeof r.out!=="undefined"&&t!=="in"&&i in r.out&&(t||r.key!==i)&&(n=chain(n,createIteratorForKey(r.out,i)))}e!=="directed"&&typeof r.undirected!=="undefined"&&i in r.undirected&&(n=chain(n,createIteratorForKey(r.undirected,i)));return n}
/**
 * Function attaching an edge array creator method to the Graph prototype.
 *
 * @param {function} Class       - Target class.
 * @param {object}   description - Method description.
 */function attachEdgeArrayCreator(e,t){const{name:r,type:i,direction:n}=t;
/**
   * Function returning an array of certain edges.
   *
   * Arity 0: Return all the relevant edges.
   *
   * Arity 1: Return all of a node's relevant edges.
   * @param  {any}   node   - Target node.
   *
   * Arity 2: Return the relevant edges across the given path.
   * @param  {any}   source - Source node.
   * @param  {any}   target - Target node.
   *
   * @return {array|number} - The edges or the number of edges.
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */e.prototype[r]=function(e,t){if(i!=="mixed"&&this.type!=="mixed"&&i!==this.type)return[];if(!arguments.length)return createEdgeArray(this,i);if(arguments.length===1){e=""+e;const t=this._nodes.get(e);if(typeof t==="undefined")throw new NotFoundGraphError(`Graph.${r}: could not find the "${e}" node in the graph.`);return createEdgeArrayForNode(this.multi,i==="mixed"?this.type:i,n,t)}if(arguments.length===2){e=""+e;t=""+t;const o=this._nodes.get(e);if(!o)throw new NotFoundGraphError(`Graph.${r}:  could not find the "${e}" source node in the graph.`);if(!this._nodes.has(t))throw new NotFoundGraphError(`Graph.${r}:  could not find the "${t}" target node in the graph.`);return createEdgeArrayForPath(i,this.multi,n,o,t)}throw new InvalidArgumentsGraphError(`Graph.${r}: too many arguments (expecting 0, 1 or 2 and got ${arguments.length}).`)}}
/**
 * Function attaching a edge callback iterator method to the Graph prototype.
 *
 * @param {function} Class       - Target class.
 * @param {object}   description - Method description.
 */function attachForEachEdge(e,t){const{name:r,type:i,direction:n}=t;const o="forEach"+r[0].toUpperCase()+r.slice(1,-1);
/**
   * Function iterating over the graph's relevant edges by applying the given
   * callback.
   *
   * Arity 1: Iterate over all the relevant edges.
   * @param  {function} callback - Callback to use.
   *
   * Arity 2: Iterate over all of a node's relevant edges.
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   *
   * Arity 3: Iterate over the relevant edges across the given path.
   * @param  {any}      source   - Source node.
   * @param  {any}      target   - Target node.
   * @param  {function} callback - Callback to use.
   *
   * @return {undefined}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */e.prototype[o]=function(e,t,r){if(i==="mixed"||this.type==="mixed"||i===this.type){if(arguments.length===1){r=e;return forEachEdge(false,this,i,r)}if(arguments.length===2){e=""+e;r=t;const a=this._nodes.get(e);if(typeof a==="undefined")throw new NotFoundGraphError(`Graph.${o}: could not find the "${e}" node in the graph.`);return forEachEdgeForNode(false,this.multi,i==="mixed"?this.type:i,n,a,r)}if(arguments.length===3){e=""+e;t=""+t;const a=this._nodes.get(e);if(!a)throw new NotFoundGraphError(`Graph.${o}:  could not find the "${e}" source node in the graph.`);if(!this._nodes.has(t))throw new NotFoundGraphError(`Graph.${o}:  could not find the "${t}" target node in the graph.`);return forEachEdgeForPath(false,i,this.multi,n,a,t,r)}throw new InvalidArgumentsGraphError(`Graph.${o}: too many arguments (expecting 1, 2 or 3 and got ${arguments.length}).`)}};
/**
   * Function mapping the graph's relevant edges by applying the given
   * callback.
   *
   * Arity 1: Map all the relevant edges.
   * @param  {function} callback - Callback to use.
   *
   * Arity 2: Map all of a node's relevant edges.
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   *
   * Arity 3: Map the relevant edges across the given path.
   * @param  {any}      source   - Source node.
   * @param  {any}      target   - Target node.
   * @param  {function} callback - Callback to use.
   *
   * @return {undefined}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const a="map"+r[0].toUpperCase()+r.slice(1);e.prototype[a]=function(){const e=Array.prototype.slice.call(arguments);const t=e.pop();let r;if(e.length===0){let n=0;i!=="directed"&&(n+=this.undirectedSize);i!=="undirected"&&(n+=this.directedSize);r=new Array(n);let o=0;e.push(((e,i,n,a,d,s,h)=>{r[o++]=t(e,i,n,a,d,s,h)}))}else{r=[];e.push(((e,i,n,o,a,d,s)=>{r.push(t(e,i,n,o,a,d,s))}))}this[o].apply(this,e);return r};
/**
   * Function filtering the graph's relevant edges using the provided predicate
   * function.
   *
   * Arity 1: Filter all the relevant edges.
   * @param  {function} predicate - Predicate to use.
   *
   * Arity 2: Filter all of a node's relevant edges.
   * @param  {any}      node      - Target node.
   * @param  {function} predicate - Predicate to use.
   *
   * Arity 3: Filter the relevant edges across the given path.
   * @param  {any}      source    - Source node.
   * @param  {any}      target    - Target node.
   * @param  {function} predicate - Predicate to use.
   *
   * @return {undefined}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const d="filter"+r[0].toUpperCase()+r.slice(1);e.prototype[d]=function(){const e=Array.prototype.slice.call(arguments);const t=e.pop();const r=[];e.push(((e,i,n,o,a,d,s)=>{t(e,i,n,o,a,d,s)&&r.push(e)}));this[o].apply(this,e);return r};
/**
   * Function reducing the graph's relevant edges using the provided accumulator
   * function.
   *
   * Arity 1: Reduce all the relevant edges.
   * @param  {function} accumulator  - Accumulator to use.
   * @param  {any}      initialValue - Initial value.
   *
   * Arity 2: Reduce all of a node's relevant edges.
   * @param  {any}      node         - Target node.
   * @param  {function} accumulator  - Accumulator to use.
   * @param  {any}      initialValue - Initial value.
   *
   * Arity 3: Reduce the relevant edges across the given path.
   * @param  {any}      source       - Source node.
   * @param  {any}      target       - Target node.
   * @param  {function} accumulator  - Accumulator to use.
   * @param  {any}      initialValue - Initial value.
   *
   * @return {undefined}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const s="reduce"+r[0].toUpperCase()+r.slice(1);e.prototype[s]=function(){let e=Array.prototype.slice.call(arguments);if(e.length<2||e.length>4)throw new InvalidArgumentsGraphError(`Graph.${s}: invalid number of arguments (expecting 2, 3 or 4 and got ${e.length}).`);if(typeof e[e.length-1]==="function"&&typeof e[e.length-2]!=="function")throw new InvalidArgumentsGraphError(`Graph.${s}: missing initial value. You must provide it because the callback takes more than one argument and we cannot infer the initial value from the first iteration, as you could with a simple array.`);let t;let r;if(e.length===2){t=e[0];r=e[1];e=[]}else if(e.length===3){t=e[1];r=e[2];e=[e[0]]}else if(e.length===4){t=e[2];r=e[3];e=[e[0],e[1]]}let i=r;e.push(((e,r,n,o,a,d,s)=>{i=t(i,e,r,n,o,a,d,s)}));this[o].apply(this,e);return i}}
/**
 * Function attaching a breakable edge callback iterator method to the Graph
 * prototype.
 *
 * @param {function} Class       - Target class.
 * @param {object}   description - Method description.
 */function attachFindEdge(e,t){const{name:r,type:i,direction:n}=t;const o="find"+r[0].toUpperCase()+r.slice(1,-1);
/**
   * Function iterating over the graph's relevant edges in order to match
   * one of them using the provided predicate function.
   *
   * Arity 1: Iterate over all the relevant edges.
   * @param  {function} callback - Callback to use.
   *
   * Arity 2: Iterate over all of a node's relevant edges.
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   *
   * Arity 3: Iterate over the relevant edges across the given path.
   * @param  {any}      source   - Source node.
   * @param  {any}      target   - Target node.
   * @param  {function} callback - Callback to use.
   *
   * @return {undefined}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */e.prototype[o]=function(e,t,r){if(i!=="mixed"&&this.type!=="mixed"&&i!==this.type)return false;if(arguments.length===1){r=e;return forEachEdge(true,this,i,r)}if(arguments.length===2){e=""+e;r=t;const a=this._nodes.get(e);if(typeof a==="undefined")throw new NotFoundGraphError(`Graph.${o}: could not find the "${e}" node in the graph.`);return forEachEdgeForNode(true,this.multi,i==="mixed"?this.type:i,n,a,r)}if(arguments.length===3){e=""+e;t=""+t;const a=this._nodes.get(e);if(!a)throw new NotFoundGraphError(`Graph.${o}:  could not find the "${e}" source node in the graph.`);if(!this._nodes.has(t))throw new NotFoundGraphError(`Graph.${o}:  could not find the "${t}" target node in the graph.`);return forEachEdgeForPath(true,i,this.multi,n,a,t,r)}throw new InvalidArgumentsGraphError(`Graph.${o}: too many arguments (expecting 1, 2 or 3 and got ${arguments.length}).`)};
/**
   * Function iterating over the graph's relevant edges in order to assert
   * whether any one of them matches the provided predicate function.
   *
   * Arity 1: Iterate over all the relevant edges.
   * @param  {function} callback - Callback to use.
   *
   * Arity 2: Iterate over all of a node's relevant edges.
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   *
   * Arity 3: Iterate over the relevant edges across the given path.
   * @param  {any}      source   - Source node.
   * @param  {any}      target   - Target node.
   * @param  {function} callback - Callback to use.
   *
   * @return {undefined}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const a="some"+r[0].toUpperCase()+r.slice(1,-1);e.prototype[a]=function(){const e=Array.prototype.slice.call(arguments);const t=e.pop();e.push(((e,r,i,n,o,a,d)=>t(e,r,i,n,o,a,d)));const r=this[o].apply(this,e);return!!r};
/**
   * Function iterating over the graph's relevant edges in order to assert
   * whether all of them matche the provided predicate function.
   *
   * Arity 1: Iterate over all the relevant edges.
   * @param  {function} callback - Callback to use.
   *
   * Arity 2: Iterate over all of a node's relevant edges.
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   *
   * Arity 3: Iterate over the relevant edges across the given path.
   * @param  {any}      source   - Source node.
   * @param  {any}      target   - Target node.
   * @param  {function} callback - Callback to use.
   *
   * @return {undefined}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const d="every"+r[0].toUpperCase()+r.slice(1,-1);e.prototype[d]=function(){const e=Array.prototype.slice.call(arguments);const t=e.pop();e.push(((e,r,i,n,o,a,d)=>!t(e,r,i,n,o,a,d)));const r=this[o].apply(this,e);return!r}}
/**
 * Function attaching an edge iterator method to the Graph prototype.
 *
 * @param {function} Class       - Target class.
 * @param {object}   description - Method description.
 */function attachEdgeIteratorCreator(e,t){const{name:r,type:i,direction:n}=t;const o=r.slice(0,-1)+"Entries";
/**
   * Function returning an iterator over the graph's edges.
   *
   * Arity 0: Iterate over all the relevant edges.
   *
   * Arity 1: Iterate over all of a node's relevant edges.
   * @param  {any}   node   - Target node.
   *
   * Arity 2: Iterate over the relevant edges across the given path.
   * @param  {any}   source - Source node.
   * @param  {any}   target - Target node.
   *
   * @return {array|number} - The edges or the number of edges.
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */e.prototype[o]=function(e,t){if(i!=="mixed"&&this.type!=="mixed"&&i!==this.type)return emptyIterator();if(!arguments.length)return createEdgeIterator(this,i);if(arguments.length===1){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.${o}: could not find the "${e}" node in the graph.`);return createEdgeIteratorForNode(i,n,t)}if(arguments.length===2){e=""+e;t=""+t;const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.${o}:  could not find the "${e}" source node in the graph.`);if(!this._nodes.has(t))throw new NotFoundGraphError(`Graph.${o}:  could not find the "${t}" target node in the graph.`);return createEdgeIteratorForPath(i,n,r,t)}throw new InvalidArgumentsGraphError(`Graph.${o}: too many arguments (expecting 0, 1 or 2 and got ${arguments.length}).`)}}
/**
 * Function attaching every edge iteration method to the Graph class.
 *
 * @param {function} Graph - Graph class.
 */function attachEdgeIterationMethods(e){s.forEach((t=>{attachEdgeArrayCreator(e,t);attachForEachEdge(e,t);attachFindEdge(e,t);attachEdgeIteratorCreator(e,t)}))}const h=[{name:"neighbors",type:"mixed"},{name:"inNeighbors",type:"directed",direction:"in"},{name:"outNeighbors",type:"directed",direction:"out"},{name:"inboundNeighbors",type:"mixed",direction:"in"},{name:"outboundNeighbors",type:"mixed",direction:"out"},{name:"directedNeighbors",type:"directed"},{name:"undirectedNeighbors",type:"undirected"}];function CompositeSetWrapper(){this.A=null;this.B=null}CompositeSetWrapper.prototype.wrap=function(e){this.A===null?this.A=e:this.B===null&&(this.B=e)};CompositeSetWrapper.prototype.has=function(e){return this.A!==null&&e in this.A||this.B!==null&&e in this.B};
/**
 * Function iterating over the given node's relevant neighbors to match
 * one of them using a predicated function.
 *
 * @param  {string}   type      - Type of neighbors.
 * @param  {string}   direction - Direction.
 * @param  {any}      nodeData  - Target node's data.
 * @param  {function} callback  - Callback to use.
 */function forEachInObjectOnce(e,t,r,i,n){for(const o in i){const a=i[o];const d=a.source;const s=a.target;const h=d===r?s:d;if(t&&t.has(h.key))continue;const u=n(h.key,h.attributes);if(e&&u)return h.key}}function forEachNeighbor(e,t,r,i,n){if(t!=="mixed"){if(t==="undirected")return forEachInObjectOnce(e,null,i,i.undirected,n);if(typeof r==="string")return forEachInObjectOnce(e,null,i,i[r],n)}const o=new CompositeSetWrapper;let a;if(t!=="undirected"){if(r!=="out"){a=forEachInObjectOnce(e,null,i,i.in,n);if(e&&a)return a;o.wrap(i.in)}if(r!=="in"){a=forEachInObjectOnce(e,o,i,i.out,n);if(e&&a)return a;o.wrap(i.out)}}if(t!=="directed"){a=forEachInObjectOnce(e,o,i,i.undirected,n);if(e&&a)return a}}
/**
 * Function creating an array of relevant neighbors for the given node.
 *
 * @param  {string}       type      - Type of neighbors.
 * @param  {string}       direction - Direction.
 * @param  {any}          nodeData  - Target node's data.
 * @return {Array}                  - The list of neighbors.
 */function createNeighborArrayForNode(e,t,r){if(e!=="mixed"){if(e==="undirected")return Object.keys(r.undirected);if(typeof t==="string")return Object.keys(r[t])}const i=[];forEachNeighbor(false,e,t,r,(function(e){i.push(e)}));return i}
/**
 * Function returning an iterator over the given node's relevant neighbors.
 *
 * @param  {string}   type      - Type of neighbors.
 * @param  {string}   direction - Direction.
 * @param  {any}      nodeData  - Target node's data.
 * @return {Iterator}
 */function createDedupedObjectIterator(e,t,r){const i=Object.keys(r);const n=i.length;let o=0;return{[Symbol.iterator](){return this},next(){let a=null;do{if(o>=n){e&&e.wrap(r);return{done:true}}const d=r[i[o++]];const s=d.source;const h=d.target;a=s===t?h:s;e&&e.has(a.key)&&(a=null)}while(a===null);return{done:false,value:{neighbor:a.key,attributes:a.attributes}}}}}function createNeighborIterator(e,t,r){if(e!=="mixed"){if(e==="undirected")return createDedupedObjectIterator(null,r,r.undirected);if(typeof t==="string")return createDedupedObjectIterator(null,r,r[t])}let i=emptyIterator();const n=new CompositeSetWrapper;if(e!=="undirected"){t!=="out"&&(i=chain(i,createDedupedObjectIterator(n,r,r.in)));t!=="in"&&(i=chain(i,createDedupedObjectIterator(n,r,r.out)))}e!=="directed"&&(i=chain(i,createDedupedObjectIterator(n,r,r.undirected)));return i}
/**
 * Function attaching a neighbors array creator method to the Graph prototype.
 *
 * @param {function} Class       - Target class.
 * @param {object}   description - Method description.
 */function attachNeighborArrayCreator(e,t){const{name:r,type:i,direction:n}=t;
/**
   * Function returning an array of certain neighbors.
   *
   * @param  {any}   node   - Target node.
   * @return {array} - The neighbors of neighbors.
   *
   * @throws {Error} - Will throw if node is not found in the graph.
   */e.prototype[r]=function(e){if(i!=="mixed"&&this.type!=="mixed"&&i!==this.type)return[];e=""+e;const t=this._nodes.get(e);if(typeof t==="undefined")throw new NotFoundGraphError(`Graph.${r}: could not find the "${e}" node in the graph.`);return createNeighborArrayForNode(i==="mixed"?this.type:i,n,t)}}
/**
 * Function attaching a neighbors callback iterator method to the Graph prototype.
 *
 * @param {function} Class       - Target class.
 * @param {object}   description - Method description.
 */function attachForEachNeighbor(e,t){const{name:r,type:i,direction:n}=t;const o="forEach"+r[0].toUpperCase()+r.slice(1,-1);
/**
   * Function iterating over all the relevant neighbors using a callback.
   *
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   * @return {undefined}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */e.prototype[o]=function(e,t){if(i!=="mixed"&&this.type!=="mixed"&&i!==this.type)return;e=""+e;const r=this._nodes.get(e);if(typeof r==="undefined")throw new NotFoundGraphError(`Graph.${o}: could not find the "${e}" node in the graph.`);forEachNeighbor(false,i==="mixed"?this.type:i,n,r,t)};
/**
   * Function mapping the relevant neighbors using a callback.
   *
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const a="map"+r[0].toUpperCase()+r.slice(1);e.prototype[a]=function(e,t){const r=[];this[o](e,((e,i)=>{r.push(t(e,i))}));return r};
/**
   * Function filtering the relevant neighbors using a callback.
   *
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const d="filter"+r[0].toUpperCase()+r.slice(1);e.prototype[d]=function(e,t){const r=[];this[o](e,((e,i)=>{t(e,i)&&r.push(e)}));return r};
/**
   * Function reducing the relevant neighbors using a callback.
   *
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const s="reduce"+r[0].toUpperCase()+r.slice(1);e.prototype[s]=function(e,t,r){if(arguments.length<3)throw new InvalidArgumentsGraphError(`Graph.${s}: missing initial value. You must provide it because the callback takes more than one argument and we cannot infer the initial value from the first iteration, as you could with a simple array.`);let i=r;this[o](e,((e,r)=>{i=t(i,e,r)}));return i}}
/**
 * Function attaching a breakable neighbors callback iterator method to the
 * Graph prototype.
 *
 * @param {function} Class       - Target class.
 * @param {object}   description - Method description.
 */function attachFindNeighbor(e,t){const{name:r,type:i,direction:n}=t;const o=r[0].toUpperCase()+r.slice(1,-1);const a="find"+o;
/**
   * Function iterating over all the relevant neighbors using a callback.
   *
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   * @return {undefined}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */e.prototype[a]=function(e,t){if(i!=="mixed"&&this.type!=="mixed"&&i!==this.type)return;e=""+e;const r=this._nodes.get(e);if(typeof r==="undefined")throw new NotFoundGraphError(`Graph.${a}: could not find the "${e}" node in the graph.`);return forEachNeighbor(true,i==="mixed"?this.type:i,n,r,t)};
/**
   * Function iterating over all the relevant neighbors to find if any of them
   * matches the given predicate.
   *
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const d="some"+o;e.prototype[d]=function(e,t){const r=this[a](e,t);return!!r};
/**
   * Function iterating over all the relevant neighbors to find if all of them
   * matche the given predicate.
   *
   * @param  {any}      node     - Target node.
   * @param  {function} callback - Callback to use.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */const s="every"+o;e.prototype[s]=function(e,t){const r=this[a](e,((e,r)=>!t(e,r)));return!r}}
/**
 * Function attaching a neighbors callback iterator method to the Graph prototype.
 *
 * @param {function} Class       - Target class.
 * @param {object}   description - Method description.
 */function attachNeighborIteratorCreator(e,t){const{name:r,type:i,direction:n}=t;const o=r.slice(0,-1)+"Entries";
/**
   * Function returning an iterator over all the relevant neighbors.
   *
   * @param  {any}      node     - Target node.
   * @return {Iterator}
   *
   * @throws {Error} - Will throw if there are too many arguments.
   */e.prototype[o]=function(e){if(i!=="mixed"&&this.type!=="mixed"&&i!==this.type)return emptyIterator();e=""+e;const t=this._nodes.get(e);if(typeof t==="undefined")throw new NotFoundGraphError(`Graph.${o}: could not find the "${e}" node in the graph.`);return createNeighborIterator(i==="mixed"?this.type:i,n,t)}}
/**
 * Function attaching every neighbor iteration method to the Graph class.
 *
 * @param {function} Graph - Graph class.
 */function attachNeighborIterationMethods(e){h.forEach((t=>{attachNeighborArrayCreator(e,t);attachForEachNeighbor(e,t);attachFindNeighbor(e,t);attachNeighborIteratorCreator(e,t)}))}
/**
 * Function iterating over a simple graph's adjacency using a callback.
 *
 * @param {boolean}  breakable         - Can we break?
 * @param {boolean}  assymetric        - Whether to emit undirected edges only once.
 * @param {boolean}  disconnectedNodes - Whether to emit disconnected nodes.
 * @param {Graph}    graph             - Target Graph instance.
 * @param {callback} function          - Iteration callback.
 */function forEachAdjacency(e,t,r,i,n){const o=i._nodes.values();const a=i.type;let d,s,h,u,c,p,l;while(d=o.next(),d.done!==true){let i=false;s=d.value;if(a!=="undirected"){u=s.out;for(h in u){c=u[h];do{p=c.target;i=true;l=n(s.key,p.key,s.attributes,p.attributes,c.key,c.attributes,c.undirected);if(e&&l)return c;c=c.next}while(c)}}if(a!=="directed"){u=s.undirected;for(h in u)if(!(t&&s.key>h)){c=u[h];do{p=c.target;p.key!==h&&(p=c.source);i=true;l=n(s.key,p.key,s.attributes,p.attributes,c.key,c.attributes,c.undirected);if(e&&l)return c;c=c.next}while(c)}}if(r&&!i){l=n(s.key,null,s.attributes,null,null,null,null);if(e&&l)return null}}}
/**
 * Formats internal node data into a serialized node.
 *
 * @param  {any}    key  - The node's key.
 * @param  {object} data - Internal node's data.
 * @return {array}       - The serialized node.
 */function serializeNode(e,r){const i={key:e};isEmpty(r.attributes)||(i.attributes=t({},r.attributes));return i}
/**
 * Formats internal edge data into a serialized edge.
 *
 * @param  {string} type - The graph's type.
 * @param  {any}    key  - The edge's key.
 * @param  {object} data - Internal edge's data.
 * @return {array}       - The serialized edge.
 */function serializeEdge(e,r,i){const n={key:r,source:i.source.key,target:i.target.key};isEmpty(i.attributes)||(n.attributes=t({},i.attributes));e==="mixed"&&i.undirected&&(n.undirected=true);return n}
/**
 * Checks whether the given value is a serialized node.
 *
 * @param  {mixed} value - Target value.
 * @return {string|null}
 */function validateSerializedNode(e){if(!isPlainObject(e))throw new InvalidArgumentsGraphError('Graph.import: invalid serialized node. A serialized node should be a plain object with at least a "key" property.');if(!("key"in e))throw new InvalidArgumentsGraphError("Graph.import: serialized node is missing its key.");if("attributes"in e&&(!isPlainObject(e.attributes)||e.attributes===null))throw new InvalidArgumentsGraphError("Graph.import: invalid attributes. Attributes should be a plain object, null or omitted.")}
/**
 * Checks whether the given value is a serialized edge.
 *
 * @param  {mixed} value - Target value.
 * @return {string|null}
 */function validateSerializedEdge(e){if(!isPlainObject(e))throw new InvalidArgumentsGraphError('Graph.import: invalid serialized edge. A serialized edge should be a plain object with at least a "source" & "target" property.');if(!("source"in e))throw new InvalidArgumentsGraphError("Graph.import: serialized edge is missing its source.");if(!("target"in e))throw new InvalidArgumentsGraphError("Graph.import: serialized edge is missing its target.");if("attributes"in e&&(!isPlainObject(e.attributes)||e.attributes===null))throw new InvalidArgumentsGraphError("Graph.import: invalid attributes. Attributes should be a plain object, null or omitted.");if("undirected"in e&&typeof e.undirected!=="boolean")throw new InvalidArgumentsGraphError("Graph.import: invalid undirectedness information. Undirected should be boolean or omitted.")}const u=incrementalIdStartingFromRandomByte();const c=new Set(["directed","undirected","mixed"]);const p=new Set(["domain","_events","_eventsCount","_maxListeners"]);const l=[{name:e=>`${e}Edge`,generateKey:true},{name:e=>`${e}DirectedEdge`,generateKey:true,type:"directed"},{name:e=>`${e}UndirectedEdge`,generateKey:true,type:"undirected"},{name:e=>`${e}EdgeWithKey`},{name:e=>`${e}DirectedEdgeWithKey`,type:"directed"},{name:e=>`${e}UndirectedEdgeWithKey`,type:"undirected"}];const g={allowSelfLoops:true,multi:false,type:"mixed"};
/**
 * Internal method used to add a node to the given graph
 *
 * @param  {Graph}   graph           - Target graph.
 * @param  {any}     node            - The node's key.
 * @param  {object}  [attributes]    - Optional attributes.
 * @return {NodeData}                - Created node data.
 */function addNode(e,t,r){if(r&&!isPlainObject(r))throw new InvalidArgumentsGraphError(`Graph.addNode: invalid attributes. Expecting an object but got "${r}"`);t=""+t;r=r||{};if(e._nodes.has(t))throw new UsageGraphError(`Graph.addNode: the "${t}" node already exist in the graph.`);const i=new e.NodeDataClass(t,r);e._nodes.set(t,i);e.emit("nodeAdded",{key:t,attributes:r});return i}function unsafeAddNode(e,t,r){const i=new e.NodeDataClass(t,r);e._nodes.set(t,i);e.emit("nodeAdded",{key:t,attributes:r});return i}
/**
 * Internal method used to add an arbitrary edge to the given graph.
 *
 * @param  {Graph}   graph           - Target graph.
 * @param  {string}  name            - Name of the child method for errors.
 * @param  {boolean} mustGenerateKey - Should the graph generate an id?
 * @param  {boolean} undirected      - Whether the edge is undirected.
 * @param  {any}     edge            - The edge's key.
 * @param  {any}     source          - The source node.
 * @param  {any}     target          - The target node.
 * @param  {object}  [attributes]    - Optional attributes.
 * @return {any}                     - The edge.
 *
 * @throws {Error} - Will throw if the graph is of the wrong type.
 * @throws {Error} - Will throw if the given attributes are not an object.
 * @throws {Error} - Will throw if source or target doesn't exist.
 * @throws {Error} - Will throw if the edge already exist.
 */function addEdge(e,t,r,i,n,o,a,d){if(!i&&e.type==="undirected")throw new UsageGraphError(`Graph.${t}: you cannot add a directed edge to an undirected graph. Use the #.addEdge or #.addUndirectedEdge instead.`);if(i&&e.type==="directed")throw new UsageGraphError(`Graph.${t}: you cannot add an undirected edge to a directed graph. Use the #.addEdge or #.addDirectedEdge instead.`);if(d&&!isPlainObject(d))throw new InvalidArgumentsGraphError(`Graph.${t}: invalid attributes. Expecting an object but got "${d}"`);o=""+o;a=""+a;d=d||{};if(!e.allowSelfLoops&&o===a)throw new UsageGraphError(`Graph.${t}: source & target are the same ("${o}"), thus creating a loop explicitly forbidden by this graph 'allowSelfLoops' option set to false.`);const s=e._nodes.get(o),h=e._nodes.get(a);if(!s)throw new NotFoundGraphError(`Graph.${t}: source node "${o}" not found.`);if(!h)throw new NotFoundGraphError(`Graph.${t}: target node "${a}" not found.`);const u={key:null,undirected:i,source:o,target:a,attributes:d};if(r)n=e._edgeKeyGenerator();else{n=""+n;if(e._edges.has(n))throw new UsageGraphError(`Graph.${t}: the "${n}" edge already exists in the graph.`)}if(!e.multi&&(i?typeof s.undirected[a]!=="undefined":typeof s.out[a]!=="undefined"))throw new UsageGraphError(`Graph.${t}: an edge linking "${o}" to "${a}" already exists. If you really want to add multiple edges linking those nodes, you should create a multi graph by using the 'multi' option.`);const c=new EdgeData(i,n,s,h,d);e._edges.set(n,c);const p=o===a;if(i){s.undirectedDegree++;h.undirectedDegree++;if(p){s.undirectedLoops++;e._undirectedSelfLoopCount++}}else{s.outDegree++;h.inDegree++;if(p){s.directedLoops++;e._directedSelfLoopCount++}}e.multi?c.attachMulti():c.attach();i?e._undirectedSize++:e._directedSize++;u.key=n;e.emit("edgeAdded",u);return n}
/**
 * Internal method used to add an arbitrary edge to the given graph.
 *
 * @param  {Graph}   graph           - Target graph.
 * @param  {string}  name            - Name of the child method for errors.
 * @param  {boolean} mustGenerateKey - Should the graph generate an id?
 * @param  {boolean} undirected      - Whether the edge is undirected.
 * @param  {any}     edge            - The edge's key.
 * @param  {any}     source          - The source node.
 * @param  {any}     target          - The target node.
 * @param  {object}  [attributes]    - Optional attributes.
 * @param  {boolean} [asUpdater]       - Are we updating or merging?
 * @return {any}                     - The edge.
 *
 * @throws {Error} - Will throw if the graph is of the wrong type.
 * @throws {Error} - Will throw if the given attributes are not an object.
 * @throws {Error} - Will throw if source or target doesn't exist.
 * @throws {Error} - Will throw if the edge already exist.
 */function mergeEdge(e,r,i,n,o,a,d,s,h){if(!n&&e.type==="undirected")throw new UsageGraphError(`Graph.${r}: you cannot merge/update a directed edge to an undirected graph. Use the #.mergeEdge/#.updateEdge or #.addUndirectedEdge instead.`);if(n&&e.type==="directed")throw new UsageGraphError(`Graph.${r}: you cannot merge/update an undirected edge to a directed graph. Use the #.mergeEdge/#.updateEdge or #.addDirectedEdge instead.`);if(s)if(h){if(typeof s!=="function")throw new InvalidArgumentsGraphError(`Graph.${r}: invalid updater function. Expecting a function but got "${s}"`)}else if(!isPlainObject(s))throw new InvalidArgumentsGraphError(`Graph.${r}: invalid attributes. Expecting an object but got "${s}"`);a=""+a;d=""+d;let u;if(h){u=s;s=void 0}if(!e.allowSelfLoops&&a===d)throw new UsageGraphError(`Graph.${r}: source & target are the same ("${a}"), thus creating a loop explicitly forbidden by this graph 'allowSelfLoops' option set to false.`);let c=e._nodes.get(a);let p=e._nodes.get(d);let l;let g;if(!i){l=e._edges.get(o);if(l){if((l.source.key!==a||l.target.key!==d)&&(!n||l.source.key!==d||l.target.key!==a))throw new UsageGraphError(`Graph.${r}: inconsistency detected when attempting to merge the "${o}" edge with "${a}" source & "${d}" target vs. ("${l.source.key}", "${l.target.key}").`);g=l}}g||e.multi||!c||(g=n?c.undirected[d]:c.out[d]);if(g){const r=[g.key,false,false,false];if(h?!u:!s)return r;if(h){const t=g.attributes;g.attributes=u(t);e.emit("edgeAttributesUpdated",{type:"replace",key:g.key,attributes:g.attributes})}else{t(g.attributes,s);e.emit("edgeAttributesUpdated",{type:"merge",key:g.key,attributes:g.attributes,data:s})}return r}s=s||{};h&&u&&(s=u(s));const f={key:null,undirected:n,source:a,target:d,attributes:s};if(i)o=e._edgeKeyGenerator();else{o=""+o;if(e._edges.has(o))throw new UsageGraphError(`Graph.${r}: the "${o}" edge already exists in the graph.`)}let y=false;let b=false;if(!c){c=unsafeAddNode(e,a,{});y=true;if(a===d){p=c;b=true}}if(!p){p=unsafeAddNode(e,d,{});b=true}l=new EdgeData(n,o,c,p,s);e._edges.set(o,l);const w=a===d;if(n){c.undirectedDegree++;p.undirectedDegree++;if(w){c.undirectedLoops++;e._undirectedSelfLoopCount++}}else{c.outDegree++;p.inDegree++;if(w){c.directedLoops++;e._directedSelfLoopCount++}}e.multi?l.attachMulti():l.attach();n?e._undirectedSize++:e._directedSize++;f.key=o;e.emit("edgeAdded",f);return[o,true,y,b]}
/**
 * Internal method used to drop an edge.
 *
 * @param  {Graph}    graph    - Target graph.
 * @param  {EdgeData} edgeData - Data of the edge to drop.
 */function dropEdgeFromData(e,t){e._edges.delete(t.key);const{source:r,target:i,attributes:n}=t;const o=t.undirected;const a=r===i;if(o){r.undirectedDegree--;i.undirectedDegree--;if(a){r.undirectedLoops--;e._undirectedSelfLoopCount--}}else{r.outDegree--;i.inDegree--;if(a){r.directedLoops--;e._directedSelfLoopCount--}}e.multi?t.detachMulti():t.detach();o?e._undirectedSize--:e._directedSize--;e.emit("edgeDropped",{key:t.key,attributes:n,source:r.key,target:i.key,undirected:o})}
/**
 * Graph class
 *
 * @constructor
 * @param  {object}  [options] - Options:
 * @param  {boolean}   [allowSelfLoops] - Allow self loops?
 * @param  {string}    [type]           - Type of the graph.
 * @param  {boolean}   [map]            - Allow references as keys?
 * @param  {boolean}   [multi]          - Allow parallel edges?
 *
 * @throws {Error} - Will throw if the arguments are not valid.
 */class Graph extends e{constructor(e){super();e=t({},g,e);if(typeof e.multi!=="boolean")throw new InvalidArgumentsGraphError(`Graph.constructor: invalid 'multi' option. Expecting a boolean but got "${e.multi}".`);if(!c.has(e.type))throw new InvalidArgumentsGraphError(`Graph.constructor: invalid 'type' option. Should be one of "mixed", "directed" or "undirected" but got "${e.type}".`);if(typeof e.allowSelfLoops!=="boolean")throw new InvalidArgumentsGraphError(`Graph.constructor: invalid 'allowSelfLoops' option. Expecting a boolean but got "${e.allowSelfLoops}".`);const r=e.type==="mixed"?MixedNodeData:e.type==="directed"?DirectedNodeData:UndirectedNodeData;privateProperty(this,"NodeDataClass",r);const i="geid_"+u()+"_";let n=0;const edgeKeyGenerator=()=>{let e;do{e=i+n++}while(this._edges.has(e));return e};privateProperty(this,"_attributes",{});privateProperty(this,"_nodes",new Map);privateProperty(this,"_edges",new Map);privateProperty(this,"_directedSize",0);privateProperty(this,"_undirectedSize",0);privateProperty(this,"_directedSelfLoopCount",0);privateProperty(this,"_undirectedSelfLoopCount",0);privateProperty(this,"_edgeKeyGenerator",edgeKeyGenerator);privateProperty(this,"_options",e);p.forEach((e=>privateProperty(this,e,this[e])));readOnlyProperty(this,"order",(()=>this._nodes.size));readOnlyProperty(this,"size",(()=>this._edges.size));readOnlyProperty(this,"directedSize",(()=>this._directedSize));readOnlyProperty(this,"undirectedSize",(()=>this._undirectedSize));readOnlyProperty(this,"selfLoopCount",(()=>this._directedSelfLoopCount+this._undirectedSelfLoopCount));readOnlyProperty(this,"directedSelfLoopCount",(()=>this._directedSelfLoopCount));readOnlyProperty(this,"undirectedSelfLoopCount",(()=>this._undirectedSelfLoopCount));readOnlyProperty(this,"multi",this._options.multi);readOnlyProperty(this,"type",this._options.type);readOnlyProperty(this,"allowSelfLoops",this._options.allowSelfLoops);readOnlyProperty(this,"implementation",(()=>"graphology"))}_resetInstanceCounters(){this._directedSize=0;this._undirectedSize=0;this._directedSelfLoopCount=0;this._undirectedSelfLoopCount=0}
/**
   * Method returning whether the given node is found in the graph.
   *
   * @param  {any}     node - The node.
   * @return {boolean}
   */hasNode(e){return this._nodes.has(""+e)}
/**
   * Method returning whether the given directed edge is found in the graph.
   *
   * Arity 1:
   * @param  {any}     edge - The edge's key.
   *
   * Arity 2:
   * @param  {any}     source - The edge's source.
   * @param  {any}     target - The edge's target.
   *
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the arguments are invalid.
   */hasDirectedEdge(e,t){if(this.type==="undirected")return false;if(arguments.length===1){const t=""+e;const r=this._edges.get(t);return!!r&&!r.undirected}if(arguments.length===2){e=""+e;t=""+t;const r=this._nodes.get(e);return!!r&&r.out.hasOwnProperty(t)}throw new InvalidArgumentsGraphError(`Graph.hasDirectedEdge: invalid arity (${arguments.length}, instead of 1 or 2). You can either ask for an edge id or for the existence of an edge between a source & a target.`)}
/**
   * Method returning whether the given undirected edge is found in the graph.
   *
   * Arity 1:
   * @param  {any}     edge - The edge's key.
   *
   * Arity 2:
   * @param  {any}     source - The edge's source.
   * @param  {any}     target - The edge's target.
   *
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the arguments are invalid.
   */hasUndirectedEdge(e,t){if(this.type==="directed")return false;if(arguments.length===1){const t=""+e;const r=this._edges.get(t);return!!r&&r.undirected}if(arguments.length===2){e=""+e;t=""+t;const r=this._nodes.get(e);return!!r&&r.undirected.hasOwnProperty(t)}throw new InvalidArgumentsGraphError(`Graph.hasDirectedEdge: invalid arity (${arguments.length}, instead of 1 or 2). You can either ask for an edge id or for the existence of an edge between a source & a target.`)}
/**
   * Method returning whether the given edge is found in the graph.
   *
   * Arity 1:
   * @param  {any}     edge - The edge's key.
   *
   * Arity 2:
   * @param  {any}     source - The edge's source.
   * @param  {any}     target - The edge's target.
   *
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the arguments are invalid.
   */hasEdge(e,t){if(arguments.length===1){const t=""+e;return this._edges.has(t)}if(arguments.length===2){e=""+e;t=""+t;const r=this._nodes.get(e);return!!r&&(typeof r.out!=="undefined"&&r.out.hasOwnProperty(t)||typeof r.undirected!=="undefined"&&r.undirected.hasOwnProperty(t))}throw new InvalidArgumentsGraphError(`Graph.hasEdge: invalid arity (${arguments.length}, instead of 1 or 2). You can either ask for an edge id or for the existence of an edge between a source & a target.`)}
/**
   * Method returning the edge matching source & target in a directed fashion.
   *
   * @param  {any} source - The edge's source.
   * @param  {any} target - The edge's target.
   *
   * @return {any|undefined}
   *
   * @throws {Error} - Will throw if the graph is multi.
   * @throws {Error} - Will throw if source or target doesn't exist.
   */directedEdge(e,t){if(this.type==="undirected")return;e=""+e;t=""+t;if(this.multi)throw new UsageGraphError("Graph.directedEdge: this method is irrelevant with multigraphs since there might be multiple edges between source & target. See #.directedEdges instead.");const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.directedEdge: could not find the "${e}" source node in the graph.`);if(!this._nodes.has(t))throw new NotFoundGraphError(`Graph.directedEdge: could not find the "${t}" target node in the graph.`);const i=r.out&&r.out[t]||void 0;return i?i.key:void 0}
/**
   * Method returning the edge matching source & target in a undirected fashion.
   *
   * @param  {any} source - The edge's source.
   * @param  {any} target - The edge's target.
   *
   * @return {any|undefined}
   *
   * @throws {Error} - Will throw if the graph is multi.
   * @throws {Error} - Will throw if source or target doesn't exist.
   */undirectedEdge(e,t){if(this.type==="directed")return;e=""+e;t=""+t;if(this.multi)throw new UsageGraphError("Graph.undirectedEdge: this method is irrelevant with multigraphs since there might be multiple edges between source & target. See #.undirectedEdges instead.");const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.undirectedEdge: could not find the "${e}" source node in the graph.`);if(!this._nodes.has(t))throw new NotFoundGraphError(`Graph.undirectedEdge: could not find the "${t}" target node in the graph.`);const i=r.undirected&&r.undirected[t]||void 0;return i?i.key:void 0}
/**
   * Method returning the edge matching source & target in a mixed fashion.
   *
   * @param  {any} source - The edge's source.
   * @param  {any} target - The edge's target.
   *
   * @return {any|undefined}
   *
   * @throws {Error} - Will throw if the graph is multi.
   * @throws {Error} - Will throw if source or target doesn't exist.
   */edge(e,t){if(this.multi)throw new UsageGraphError("Graph.edge: this method is irrelevant with multigraphs since there might be multiple edges between source & target. See #.edges instead.");e=""+e;t=""+t;const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.edge: could not find the "${e}" source node in the graph.`);if(!this._nodes.has(t))throw new NotFoundGraphError(`Graph.edge: could not find the "${t}" target node in the graph.`);const i=r.out&&r.out[t]||r.undirected&&r.undirected[t]||void 0;if(i)return i.key}
/**
   * Method returning whether two nodes are directed neighbors.
   *
   * @param  {any}     node     - The node's key.
   * @param  {any}     neighbor - The neighbor's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */areDirectedNeighbors(e,t){e=""+e;t=""+t;const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.areDirectedNeighbors: could not find the "${e}" node in the graph.`);return this.type!=="undirected"&&(t in r.in||t in r.out)}
/**
   * Method returning whether two nodes are out neighbors.
   *
   * @param  {any}     node     - The node's key.
   * @param  {any}     neighbor - The neighbor's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */areOutNeighbors(e,t){e=""+e;t=""+t;const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.areOutNeighbors: could not find the "${e}" node in the graph.`);return this.type!=="undirected"&&t in r.out}
/**
   * Method returning whether two nodes are in neighbors.
   *
   * @param  {any}     node     - The node's key.
   * @param  {any}     neighbor - The neighbor's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */areInNeighbors(e,t){e=""+e;t=""+t;const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.areInNeighbors: could not find the "${e}" node in the graph.`);return this.type!=="undirected"&&t in r.in}
/**
   * Method returning whether two nodes are undirected neighbors.
   *
   * @param  {any}     node     - The node's key.
   * @param  {any}     neighbor - The neighbor's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */areUndirectedNeighbors(e,t){e=""+e;t=""+t;const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.areUndirectedNeighbors: could not find the "${e}" node in the graph.`);return this.type!=="directed"&&t in r.undirected}
/**
   * Method returning whether two nodes are neighbors.
   *
   * @param  {any}     node     - The node's key.
   * @param  {any}     neighbor - The neighbor's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */areNeighbors(e,t){e=""+e;t=""+t;const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.areNeighbors: could not find the "${e}" node in the graph.`);return this.type!=="undirected"&&(t in r.in||t in r.out)||this.type!=="directed"&&t in r.undirected}
/**
   * Method returning whether two nodes are inbound neighbors.
   *
   * @param  {any}     node     - The node's key.
   * @param  {any}     neighbor - The neighbor's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */areInboundNeighbors(e,t){e=""+e;t=""+t;const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.areInboundNeighbors: could not find the "${e}" node in the graph.`);return this.type!=="undirected"&&t in r.in||this.type!=="directed"&&t in r.undirected}
/**
   * Method returning whether two nodes are outbound neighbors.
   *
   * @param  {any}     node     - The node's key.
   * @param  {any}     neighbor - The neighbor's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */areOutboundNeighbors(e,t){e=""+e;t=""+t;const r=this._nodes.get(e);if(!r)throw new NotFoundGraphError(`Graph.areOutboundNeighbors: could not find the "${e}" node in the graph.`);return this.type!=="undirected"&&t in r.out||this.type!=="directed"&&t in r.undirected}
/**
   * Method returning the given node's in degree.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's in degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */inDegree(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.inDegree: could not find the "${e}" node in the graph.`);return this.type==="undirected"?0:t.inDegree}
/**
   * Method returning the given node's out degree.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's in degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */outDegree(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.outDegree: could not find the "${e}" node in the graph.`);return this.type==="undirected"?0:t.outDegree}
/**
   * Method returning the given node's directed degree.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's in degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */directedDegree(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.directedDegree: could not find the "${e}" node in the graph.`);return this.type==="undirected"?0:t.inDegree+t.outDegree}
/**
   * Method returning the given node's undirected degree.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's in degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */undirectedDegree(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.undirectedDegree: could not find the "${e}" node in the graph.`);return this.type==="directed"?0:t.undirectedDegree}
/**
   * Method returning the given node's inbound degree.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's inbound degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */inboundDegree(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.inboundDegree: could not find the "${e}" node in the graph.`);let r=0;this.type!=="directed"&&(r+=t.undirectedDegree);this.type!=="undirected"&&(r+=t.inDegree);return r}
/**
   * Method returning the given node's outbound degree.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's outbound degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */outboundDegree(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.outboundDegree: could not find the "${e}" node in the graph.`);let r=0;this.type!=="directed"&&(r+=t.undirectedDegree);this.type!=="undirected"&&(r+=t.outDegree);return r}
/**
   * Method returning the given node's directed degree.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */degree(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.degree: could not find the "${e}" node in the graph.`);let r=0;this.type!=="directed"&&(r+=t.undirectedDegree);this.type!=="undirected"&&(r+=t.inDegree+t.outDegree);return r}
/**
   * Method returning the given node's in degree without considering self loops.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's in degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */inDegreeWithoutSelfLoops(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.inDegreeWithoutSelfLoops: could not find the "${e}" node in the graph.`);return this.type==="undirected"?0:t.inDegree-t.directedLoops}
/**
   * Method returning the given node's out degree without considering self loops.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's in degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */outDegreeWithoutSelfLoops(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.outDegreeWithoutSelfLoops: could not find the "${e}" node in the graph.`);return this.type==="undirected"?0:t.outDegree-t.directedLoops}
/**
   * Method returning the given node's directed degree without considering self loops.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's in degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */directedDegreeWithoutSelfLoops(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.directedDegreeWithoutSelfLoops: could not find the "${e}" node in the graph.`);return this.type==="undirected"?0:t.inDegree+t.outDegree-t.directedLoops*2}
/**
   * Method returning the given node's undirected degree without considering self loops.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's in degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */undirectedDegreeWithoutSelfLoops(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.undirectedDegreeWithoutSelfLoops: could not find the "${e}" node in the graph.`);return this.type==="directed"?0:t.undirectedDegree-t.undirectedLoops*2}
/**
   * Method returning the given node's inbound degree without considering self loops.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's inbound degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */inboundDegreeWithoutSelfLoops(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.inboundDegreeWithoutSelfLoops: could not find the "${e}" node in the graph.`);let r=0;let i=0;if(this.type!=="directed"){r+=t.undirectedDegree;i+=t.undirectedLoops*2}if(this.type!=="undirected"){r+=t.inDegree;i+=t.directedLoops}return r-i}
/**
   * Method returning the given node's outbound degree without considering self loops.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's outbound degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */outboundDegreeWithoutSelfLoops(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.outboundDegreeWithoutSelfLoops: could not find the "${e}" node in the graph.`);let r=0;let i=0;if(this.type!=="directed"){r+=t.undirectedDegree;i+=t.undirectedLoops*2}if(this.type!=="undirected"){r+=t.outDegree;i+=t.directedLoops}return r-i}
/**
   * Method returning the given node's directed degree without considering self loops.
   *
   * @param  {any}     node - The node's key.
   * @return {number}       - The node's degree.
   *
   * @throws {Error} - Will throw if the node isn't in the graph.
   */degreeWithoutSelfLoops(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.degreeWithoutSelfLoops: could not find the "${e}" node in the graph.`);let r=0;let i=0;if(this.type!=="directed"){r+=t.undirectedDegree;i+=t.undirectedLoops*2}if(this.type!=="undirected"){r+=t.inDegree+t.outDegree;i+=t.directedLoops*2}return r-i}
/**
   * Method returning the given edge's source.
   *
   * @param  {any} edge - The edge's key.
   * @return {any}      - The edge's source.
   *
   * @throws {Error} - Will throw if the edge isn't in the graph.
   */source(e){e=""+e;const t=this._edges.get(e);if(!t)throw new NotFoundGraphError(`Graph.source: could not find the "${e}" edge in the graph.`);return t.source.key}
/**
   * Method returning the given edge's target.
   *
   * @param  {any} edge - The edge's key.
   * @return {any}      - The edge's target.
   *
   * @throws {Error} - Will throw if the edge isn't in the graph.
   */target(e){e=""+e;const t=this._edges.get(e);if(!t)throw new NotFoundGraphError(`Graph.target: could not find the "${e}" edge in the graph.`);return t.target.key}
/**
   * Method returning the given edge's extremities.
   *
   * @param  {any}   edge - The edge's key.
   * @return {array}      - The edge's extremities.
   *
   * @throws {Error} - Will throw if the edge isn't in the graph.
   */extremities(e){e=""+e;const t=this._edges.get(e);if(!t)throw new NotFoundGraphError(`Graph.extremities: could not find the "${e}" edge in the graph.`);return[t.source.key,t.target.key]}
/**
   * Given a node & an edge, returns the other extremity of the edge.
   *
   * @param  {any}   node - The node's key.
   * @param  {any}   edge - The edge's key.
   * @return {any}        - The related node.
   *
   * @throws {Error} - Will throw if the edge isn't in the graph or if the
   *                   edge & node are not related.
   */opposite(e,t){e=""+e;t=""+t;const r=this._edges.get(t);if(!r)throw new NotFoundGraphError(`Graph.opposite: could not find the "${t}" edge in the graph.`);const i=r.source.key;const n=r.target.key;if(e===i)return n;if(e===n)return i;throw new NotFoundGraphError(`Graph.opposite: the "${e}" node is not attached to the "${t}" edge (${i}, ${n}).`)}
/**
   * Returns whether the given edge has the given node as extremity.
   *
   * @param  {any}     edge - The edge's key.
   * @param  {any}     node - The node's key.
   * @return {boolean}      - The related node.
   *
   * @throws {Error} - Will throw if either the node or the edge isn't in the graph.
   */hasExtremity(e,t){e=""+e;t=""+t;const r=this._edges.get(e);if(!r)throw new NotFoundGraphError(`Graph.hasExtremity: could not find the "${e}" edge in the graph.`);return r.source.key===t||r.target.key===t}
/**
   * Method returning whether the given edge is undirected.
   *
   * @param  {any}     edge - The edge's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the edge isn't in the graph.
   */isUndirected(e){e=""+e;const t=this._edges.get(e);if(!t)throw new NotFoundGraphError(`Graph.isUndirected: could not find the "${e}" edge in the graph.`);return t.undirected}
/**
   * Method returning whether the given edge is directed.
   *
   * @param  {any}     edge - The edge's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the edge isn't in the graph.
   */isDirected(e){e=""+e;const t=this._edges.get(e);if(!t)throw new NotFoundGraphError(`Graph.isDirected: could not find the "${e}" edge in the graph.`);return!t.undirected}
/**
   * Method returning whether the given edge is a self loop.
   *
   * @param  {any}     edge - The edge's key.
   * @return {boolean}
   *
   * @throws {Error} - Will throw if the edge isn't in the graph.
   */isSelfLoop(e){e=""+e;const t=this._edges.get(e);if(!t)throw new NotFoundGraphError(`Graph.isSelfLoop: could not find the "${e}" edge in the graph.`);return t.source===t.target}
/**
   * Method used to add a node to the graph.
   *
   * @param  {any}    node         - The node.
   * @param  {object} [attributes] - Optional attributes.
   * @return {any}                 - The node.
   *
   * @throws {Error} - Will throw if the given node already exist.
   * @throws {Error} - Will throw if the given attributes are not an object.
   */addNode(e,t){const r=addNode(this,e,t);return r.key}
/**
   * Method used to merge a node into the graph.
   *
   * @param  {any}    node         - The node.
   * @param  {object} [attributes] - Optional attributes.
   * @return {any}                 - The node.
   */mergeNode(e,r){if(r&&!isPlainObject(r))throw new InvalidArgumentsGraphError(`Graph.mergeNode: invalid attributes. Expecting an object but got "${r}"`);e=""+e;r=r||{};let i=this._nodes.get(e);if(i){if(r){t(i.attributes,r);this.emit("nodeAttributesUpdated",{type:"merge",key:e,attributes:i.attributes,data:r})}return[e,false]}i=new this.NodeDataClass(e,r);this._nodes.set(e,i);this.emit("nodeAdded",{key:e,attributes:r});return[e,true]}
/**
   * Method used to add a node if it does not exist in the graph or else to
   * update its attributes using a function.
   *
   * @param  {any}      node      - The node.
   * @param  {function} [updater] - Optional updater function.
   * @return {any}                - The node.
   */updateNode(e,t){if(t&&typeof t!=="function")throw new InvalidArgumentsGraphError(`Graph.updateNode: invalid updater function. Expecting a function but got "${t}"`);e=""+e;let r=this._nodes.get(e);if(r){if(t){const i=r.attributes;r.attributes=t(i);this.emit("nodeAttributesUpdated",{type:"replace",key:e,attributes:r.attributes})}return[e,false]}const i=t?t({}):{};r=new this.NodeDataClass(e,i);this._nodes.set(e,r);this.emit("nodeAdded",{key:e,attributes:i});return[e,true]}
/**
   * Method used to drop a single node & all its attached edges from the graph.
   *
   * @param  {any}    node - The node.
   * @return {Graph}
   *
   * @throws {Error} - Will throw if the node doesn't exist.
   */dropNode(e){e=""+e;const t=this._nodes.get(e);if(!t)throw new NotFoundGraphError(`Graph.dropNode: could not find the "${e}" node in the graph.`);let r;if(this.type!=="undirected"){for(const e in t.out){r=t.out[e];do{dropEdgeFromData(this,r);r=r.next}while(r)}for(const e in t.in){r=t.in[e];do{dropEdgeFromData(this,r);r=r.next}while(r)}}if(this.type!=="directed")for(const e in t.undirected){r=t.undirected[e];do{dropEdgeFromData(this,r);r=r.next}while(r)}this._nodes.delete(e);this.emit("nodeDropped",{key:e,attributes:t.attributes})}
/**
   * Method used to drop a single edge from the graph.
   *
   * Arity 1:
   * @param  {any}    edge - The edge.
   *
   * Arity 2:
   * @param  {any}    source - Source node.
   * @param  {any}    target - Target node.
   *
   * @return {Graph}
   *
   * @throws {Error} - Will throw if the edge doesn't exist.
   */dropEdge(e){let t;if(arguments.length>1){const e=""+arguments[0];const r=""+arguments[1];t=getMatchingEdge(this,e,r,this.type);if(!t)throw new NotFoundGraphError(`Graph.dropEdge: could not find the "${e}" -> "${r}" edge in the graph.`)}else{e=""+e;t=this._edges.get(e);if(!t)throw new NotFoundGraphError(`Graph.dropEdge: could not find the "${e}" edge in the graph.`)}dropEdgeFromData(this,t);return this}
/**
   * Method used to drop a single directed edge from the graph.
   *
   * @param  {any}    source - Source node.
   * @param  {any}    target - Target node.
   *
   * @return {Graph}
   *
   * @throws {Error} - Will throw if the edge doesn't exist.
   */dropDirectedEdge(e,t){if(arguments.length<2)throw new UsageGraphError("Graph.dropDirectedEdge: it does not make sense to try and drop a directed edge by key. What if the edge with this key is undirected? Use #.dropEdge for this purpose instead.");if(this.multi)throw new UsageGraphError("Graph.dropDirectedEdge: cannot use a {source,target} combo when dropping an edge in a MultiGraph since we cannot infer the one you want to delete as there could be multiple ones.");e=""+e;t=""+t;const r=getMatchingEdge(this,e,t,"directed");if(!r)throw new NotFoundGraphError(`Graph.dropDirectedEdge: could not find a "${e}" -> "${t}" edge in the graph.`);dropEdgeFromData(this,r);return this}
/**
   * Method used to drop a single undirected edge from the graph.
   *
   * @param  {any}    source - Source node.
   * @param  {any}    target - Target node.
   *
   * @return {Graph}
   *
   * @throws {Error} - Will throw if the edge doesn't exist.
   */dropUndirectedEdge(e,t){if(arguments.length<2)throw new UsageGraphError("Graph.dropUndirectedEdge: it does not make sense to drop a directed edge by key. What if the edge with this key is undirected? Use #.dropEdge for this purpose instead.");if(this.multi)throw new UsageGraphError("Graph.dropUndirectedEdge: cannot use a {source,target} combo when dropping an edge in a MultiGraph since we cannot infer the one you want to delete as there could be multiple ones.");const r=getMatchingEdge(this,e,t,"undirected");if(!r)throw new NotFoundGraphError(`Graph.dropUndirectedEdge: could not find a "${e}" -> "${t}" edge in the graph.`);dropEdgeFromData(this,r);return this}clear(){this._edges.clear();this._nodes.clear();this._resetInstanceCounters();this.emit("cleared")}clearEdges(){const e=this._nodes.values();let t;while(t=e.next(),t.done!==true)t.value.clear();this._edges.clear();this._resetInstanceCounters();this.emit("edgesCleared")}
/**
   * Method returning the desired graph's attribute.
   *
   * @param  {string} name - Name of the attribute.
   * @return {any}
   */getAttribute(e){return this._attributes[e]}getAttributes(){return this._attributes}
/**
   * Method returning whether the graph has the desired attribute.
   *
   * @param  {string}  name - Name of the attribute.
   * @return {boolean}
   */hasAttribute(e){return this._attributes.hasOwnProperty(e)}
/**
   * Method setting a value for the desired graph's attribute.
   *
   * @param  {string}  name  - Name of the attribute.
   * @param  {any}     value - Value for the attribute.
   * @return {Graph}
   */setAttribute(e,t){this._attributes[e]=t;this.emit("attributesUpdated",{type:"set",attributes:this._attributes,name:e});return this}
/**
   * Method using a function to update the desired graph's attribute's value.
   *
   * @param  {string}   name    - Name of the attribute.
   * @param  {function} updater - Function use to update the attribute's value.
   * @return {Graph}
   */updateAttribute(e,t){if(typeof t!=="function")throw new InvalidArgumentsGraphError("Graph.updateAttribute: updater should be a function.");const r=this._attributes[e];this._attributes[e]=t(r);this.emit("attributesUpdated",{type:"set",attributes:this._attributes,name:e});return this}
/**
   * Method removing the desired graph's attribute.
   *
   * @param  {string} name  - Name of the attribute.
   * @return {Graph}
   */removeAttribute(e){delete this._attributes[e];this.emit("attributesUpdated",{type:"remove",attributes:this._attributes,name:e});return this}
/**
   * Method replacing the graph's attributes.
   *
   * @param  {object} attributes - New attributes.
   * @return {Graph}
   *
   * @throws {Error} - Will throw if given attributes are not a plain object.
   */replaceAttributes(e){if(!isPlainObject(e))throw new InvalidArgumentsGraphError("Graph.replaceAttributes: provided attributes are not a plain object.");this._attributes=e;this.emit("attributesUpdated",{type:"replace",attributes:this._attributes});return this}
/**
   * Method merging the graph's attributes.
   *
   * @param  {object} attributes - Attributes to merge.
   * @return {Graph}
   *
   * @throws {Error} - Will throw if given attributes are not a plain object.
   */mergeAttributes(e){if(!isPlainObject(e))throw new InvalidArgumentsGraphError("Graph.mergeAttributes: provided attributes are not a plain object.");t(this._attributes,e);this.emit("attributesUpdated",{type:"merge",attributes:this._attributes,data:e});return this}
/**
   * Method updating the graph's attributes.
   *
   * @param  {function} updater - Function used to update the attributes.
   * @return {Graph}
   *
   * @throws {Error} - Will throw if given updater is not a function.
   */updateAttributes(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.updateAttributes: provided updater is not a function.");this._attributes=e(this._attributes);this.emit("attributesUpdated",{type:"update",attributes:this._attributes});return this}
/**
   * Method used to update each node's attributes using the given function.
   *
   * @param {function}  updater - Updater function to use.
   * @param {object}    [hints] - Optional hints.
   */updateEachNodeAttributes(e,t){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.updateEachNodeAttributes: expecting an updater function.");if(t&&!validateHints(t))throw new InvalidArgumentsGraphError("Graph.updateEachNodeAttributes: invalid hints. Expecting an object having the following shape: {attributes?: [string]}");const r=this._nodes.values();let i,n;while(i=r.next(),i.done!==true){n=i.value;n.attributes=e(n.key,n.attributes)}this.emit("eachNodeAttributesUpdated",{hints:t||null})}
/**
   * Method used to update each edge's attributes using the given function.
   *
   * @param {function}  updater - Updater function to use.
   * @param {object}    [hints] - Optional hints.
   */updateEachEdgeAttributes(e,t){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.updateEachEdgeAttributes: expecting an updater function.");if(t&&!validateHints(t))throw new InvalidArgumentsGraphError("Graph.updateEachEdgeAttributes: invalid hints. Expecting an object having the following shape: {attributes?: [string]}");const r=this._edges.values();let i,n,o,a;while(i=r.next(),i.done!==true){n=i.value;o=n.source;a=n.target;n.attributes=e(n.key,n.attributes,o.key,a.key,o.attributes,a.attributes,n.undirected)}this.emit("eachEdgeAttributesUpdated",{hints:t||null})}
/**
   * Method iterating over the graph's adjacency using the given callback.
   *
   * @param  {function}  callback - Callback to use.
   */forEachAdjacencyEntry(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.forEachAdjacencyEntry: expecting a callback.");forEachAdjacency(false,false,false,this,e)}forEachAdjacencyEntryWithOrphans(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.forEachAdjacencyEntryWithOrphans: expecting a callback.");forEachAdjacency(false,false,true,this,e)}
/**
   * Method iterating over the graph's assymetric adjacency using the given callback.
   *
   * @param  {function}  callback - Callback to use.
   */forEachAssymetricAdjacencyEntry(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.forEachAssymetricAdjacencyEntry: expecting a callback.");forEachAdjacency(false,true,false,this,e)}forEachAssymetricAdjacencyEntryWithOrphans(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.forEachAssymetricAdjacencyEntryWithOrphans: expecting a callback.");forEachAdjacency(false,true,true,this,e)}nodes(){return Array.from(this._nodes.keys())}
/**
   * Method iterating over the graph's nodes using the given callback.
   *
   * @param  {function}  callback - Callback (key, attributes, index).
   */forEachNode(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.forEachNode: expecting a callback.");const t=this._nodes.values();let r,i;while(r=t.next(),r.done!==true){i=r.value;e(i.key,i.attributes)}}
/**
   * Method iterating attempting to find a node matching the given predicate
   * function.
   *
   * @param  {function}  callback - Callback (key, attributes).
   */findNode(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.findNode: expecting a callback.");const t=this._nodes.values();let r,i;while(r=t.next(),r.done!==true){i=r.value;if(e(i.key,i.attributes))return i.key}}
/**
   * Method mapping nodes.
   *
   * @param  {function}  callback - Callback (key, attributes).
   */mapNodes(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.mapNode: expecting a callback.");const t=this._nodes.values();let r,i;const n=new Array(this.order);let o=0;while(r=t.next(),r.done!==true){i=r.value;n[o++]=e(i.key,i.attributes)}return n}
/**
   * Method returning whether some node verify the given predicate.
   *
   * @param  {function}  callback - Callback (key, attributes).
   */someNode(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.someNode: expecting a callback.");const t=this._nodes.values();let r,i;while(r=t.next(),r.done!==true){i=r.value;if(e(i.key,i.attributes))return true}return false}
/**
   * Method returning whether all node verify the given predicate.
   *
   * @param  {function}  callback - Callback (key, attributes).
   */everyNode(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.everyNode: expecting a callback.");const t=this._nodes.values();let r,i;while(r=t.next(),r.done!==true){i=r.value;if(!e(i.key,i.attributes))return false}return true}
/**
   * Method filtering nodes.
   *
   * @param  {function}  callback - Callback (key, attributes).
   */filterNodes(e){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.filterNodes: expecting a callback.");const t=this._nodes.values();let r,i;const n=[];while(r=t.next(),r.done!==true){i=r.value;e(i.key,i.attributes)&&n.push(i.key)}return n}
/**
   * Method reducing nodes.
   *
   * @param  {function}  callback - Callback (accumulator, key, attributes).
   */reduceNodes(e,t){if(typeof e!=="function")throw new InvalidArgumentsGraphError("Graph.reduceNodes: expecting a callback.");if(arguments.length<2)throw new InvalidArgumentsGraphError("Graph.reduceNodes: missing initial value. You must provide it because the callback takes more than one argument and we cannot infer the initial value from the first iteration, as you could with a simple array.");let r=t;const i=this._nodes.values();let n,o;while(n=i.next(),n.done!==true){o=n.value;r=e(r,o.key,o.attributes)}return r}nodeEntries(){const e=this._nodes.values();return{[Symbol.iterator](){return this},next(){const t=e.next();if(t.done)return t;const r=t.value;return{value:{node:r.key,attributes:r.attributes},done:false}}}}export(){const e=new Array(this._nodes.size);let t=0;this._nodes.forEach(((r,i)=>{e[t++]=serializeNode(i,r)}));const r=new Array(this._edges.size);t=0;this._edges.forEach(((e,i)=>{r[t++]=serializeEdge(this.type,i,e)}));return{options:{type:this.type,multi:this.multi,allowSelfLoops:this.allowSelfLoops},attributes:this.getAttributes(),nodes:e,edges:r}}
/**
   * Method used to import a serialized graph.
   *
   * @param  {object|Graph} data  - The serialized graph.
   * @param  {boolean}      merge - Whether to merge data.
   * @return {Graph}              - Returns itself for chaining.
   */import(e,t=false){if(e instanceof Graph){e.forEachNode(((e,r)=>{t?this.mergeNode(e,r):this.addNode(e,r)}));e.forEachEdge(((e,r,i,n,o,a,d)=>{t?d?this.mergeUndirectedEdgeWithKey(e,i,n,r):this.mergeDirectedEdgeWithKey(e,i,n,r):d?this.addUndirectedEdgeWithKey(e,i,n,r):this.addDirectedEdgeWithKey(e,i,n,r)}));return this}if(!isPlainObject(e))throw new InvalidArgumentsGraphError("Graph.import: invalid argument. Expecting a serialized graph or, alternatively, a Graph instance.");if(e.attributes){if(!isPlainObject(e.attributes))throw new InvalidArgumentsGraphError("Graph.import: invalid attributes. Expecting a plain object.");t?this.mergeAttributes(e.attributes):this.replaceAttributes(e.attributes)}let r,i,n,o,a;if(e.nodes){n=e.nodes;if(!Array.isArray(n))throw new InvalidArgumentsGraphError("Graph.import: invalid nodes. Expecting an array.");for(r=0,i=n.length;r<i;r++){o=n[r];validateSerializedNode(o);const{key:e,attributes:i}=o;t?this.mergeNode(e,i):this.addNode(e,i)}}if(e.edges){let o=false;this.type==="undirected"&&(o=true);n=e.edges;if(!Array.isArray(n))throw new InvalidArgumentsGraphError("Graph.import: invalid edges. Expecting an array.");for(r=0,i=n.length;r<i;r++){a=n[r];validateSerializedEdge(a);const{source:e,target:i,attributes:d,undirected:s=o}=a;let h;if("key"in a){h=t?s?this.mergeUndirectedEdgeWithKey:this.mergeDirectedEdgeWithKey:s?this.addUndirectedEdgeWithKey:this.addDirectedEdgeWithKey;h.call(this,a.key,e,i,d)}else{h=t?s?this.mergeUndirectedEdge:this.mergeDirectedEdge:s?this.addUndirectedEdge:this.addDirectedEdge;h.call(this,e,i,d)}}}return this}
/**
   * Method returning a null copy of the graph, i.e. a graph without nodes
   * & edges but with the exact same options.
   *
   * @param  {object} options - Options to merge with the current ones.
   * @return {Graph}          - The null copy.
   */nullCopy(e){const r=new Graph(t({},this._options,e));r.replaceAttributes(t({},this.getAttributes()));return r}
/**
   * Method returning an empty copy of the graph, i.e. a graph without edges but
   * with the exact same options.
   *
   * @param  {object} options - Options to merge with the current ones.
   * @return {Graph}          - The empty copy.
   */emptyCopy(e){const r=this.nullCopy(e);this._nodes.forEach(((e,i)=>{const n=t({},e.attributes);e=new r.NodeDataClass(i,n);r._nodes.set(i,e)}));return r}
/**
   * Method returning an exact copy of the graph.
   *
   * @param  {object} options - Upgrade options.
   * @return {Graph}          - The copy.
   */copy(e){e=e||{};if(typeof e.type==="string"&&e.type!==this.type&&e.type!=="mixed")throw new UsageGraphError(`Graph.copy: cannot create an incompatible copy from "${this.type}" type to "${e.type}" because this would mean losing information about the current graph.`);if(typeof e.multi==="boolean"&&e.multi!==this.multi&&e.multi!==true)throw new UsageGraphError("Graph.copy: cannot create an incompatible copy by downgrading a multi graph to a simple one because this would mean losing information about the current graph.");if(typeof e.allowSelfLoops==="boolean"&&e.allowSelfLoops!==this.allowSelfLoops&&e.allowSelfLoops!==true)throw new UsageGraphError("Graph.copy: cannot create an incompatible copy from a graph allowing self loops to one that does not because this would mean losing information about the current graph.");const r=this.emptyCopy(e);const i=this._edges.values();let n,o;while(n=i.next(),n.done!==true){o=n.value;addEdge(r,"copy",false,o.undirected,o.key,o.source.key,o.target.key,t({},o.attributes))}return r}toJSON(){return this.export()}toString(){return"[object Graph]"}inspect(){const e={};this._nodes.forEach(((t,r)=>{e[r]=t.attributes}));const t={},r={};this._edges.forEach(((e,i)=>{const n=e.undirected?"--":"->";let o="";let a=e.source.key;let d=e.target.key;let s;if(e.undirected&&a>d){s=a;a=d;d=s}const h=`(${a})${n}(${d})`;if(i.startsWith("geid_")){if(this.multi){typeof r[h]==="undefined"?r[h]=0:r[h]++;o+=`${r[h]}. `}}else o+=`[${i}]: `;o+=h;t[o]=e.attributes}));const i={};for(const e in this)this.hasOwnProperty(e)&&!p.has(e)&&typeof this[e]!=="function"&&typeof e!=="symbol"&&(i[e]=this[e]);i.attributes=this._attributes;i.nodes=e;i.edges=t;privateProperty(i,"constructor",this.constructor);return i}}typeof Symbol!=="undefined"&&(Graph.prototype[Symbol.for("nodejs.util.inspect.custom")]=Graph.prototype.inspect);l.forEach((e=>{["add","merge","update"].forEach((t=>{const r=e.name(t);const i=t==="add"?addEdge:mergeEdge;e.generateKey?Graph.prototype[r]=function(n,o,a){return i(this,r,true,(e.type||this.type)==="undirected",null,n,o,a,t==="update")}:Graph.prototype[r]=function(n,o,a,d){return i(this,r,false,(e.type||this.type)==="undirected",n,o,a,d,t==="update")}}))}));attachNodeAttributesMethods(Graph);attachEdgeAttributesMethods(Graph);attachEdgeIterationMethods(Graph);attachNeighborIterationMethods(Graph);class DirectedGraph extends Graph{constructor(e){const r=t({type:"directed"},e);if("multi"in r&&r.multi!==false)throw new InvalidArgumentsGraphError("DirectedGraph.from: inconsistent indication that the graph should be multi in given options!");if(r.type!=="directed")throw new InvalidArgumentsGraphError('DirectedGraph.from: inconsistent "'+r.type+'" type in given options!');super(r)}}class UndirectedGraph extends Graph{constructor(e){const r=t({type:"undirected"},e);if("multi"in r&&r.multi!==false)throw new InvalidArgumentsGraphError("UndirectedGraph.from: inconsistent indication that the graph should be multi in given options!");if(r.type!=="undirected")throw new InvalidArgumentsGraphError('UndirectedGraph.from: inconsistent "'+r.type+'" type in given options!');super(r)}}class MultiGraph extends Graph{constructor(e){const r=t({multi:true},e);if("multi"in r&&r.multi!==true)throw new InvalidArgumentsGraphError("MultiGraph.from: inconsistent indication that the graph should be simple in given options!");super(r)}}class MultiDirectedGraph extends Graph{constructor(e){const r=t({type:"directed",multi:true},e);if("multi"in r&&r.multi!==true)throw new InvalidArgumentsGraphError("MultiDirectedGraph.from: inconsistent indication that the graph should be simple in given options!");if(r.type!=="directed")throw new InvalidArgumentsGraphError('MultiDirectedGraph.from: inconsistent "'+r.type+'" type in given options!');super(r)}}class MultiUndirectedGraph extends Graph{constructor(e){const r=t({type:"undirected",multi:true},e);if("multi"in r&&r.multi!==true)throw new InvalidArgumentsGraphError("MultiUndirectedGraph.from: inconsistent indication that the graph should be simple in given options!");if(r.type!=="undirected")throw new InvalidArgumentsGraphError('MultiUndirectedGraph.from: inconsistent "'+r.type+'" type in given options!');super(r)}}function attachStaticFromMethod(e){
/**
   * Builds a graph from serialized data or another graph's data.
   *
   * @param  {Graph|SerializedGraph} data      - Hydratation data.
   * @param  {object}                [options] - Options.
   * @return {Class}
   */
e.from=function(r,i){const n=t({},r.options,i);const o=new e(n);o.import(r);return o}}attachStaticFromMethod(Graph);attachStaticFromMethod(DirectedGraph);attachStaticFromMethod(UndirectedGraph);attachStaticFromMethod(MultiGraph);attachStaticFromMethod(MultiDirectedGraph);attachStaticFromMethod(MultiUndirectedGraph);Graph.Graph=Graph;Graph.DirectedGraph=DirectedGraph;Graph.UndirectedGraph=UndirectedGraph;Graph.MultiGraph=MultiGraph;Graph.MultiDirectedGraph=MultiDirectedGraph;Graph.MultiUndirectedGraph=MultiUndirectedGraph;Graph.InvalidArgumentsGraphError=InvalidArgumentsGraphError;Graph.NotFoundGraphError=NotFoundGraphError;Graph.UsageGraphError=UsageGraphError;export{DirectedGraph,Graph,InvalidArgumentsGraphError,MultiDirectedGraph,MultiGraph,MultiUndirectedGraph,NotFoundGraphError,UndirectedGraph,UsageGraphError,Graph as default};

