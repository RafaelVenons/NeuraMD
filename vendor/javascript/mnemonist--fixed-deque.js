// mnemonist/fixed-deque@0.39.8 downloaded from https://ga.jspm.io/npm:mnemonist@0.39.8/fixed-deque.js

import{e as t}from"mnemonist/_/l6VHs6WY";import*as e from"obliterator/iterator";import"obliterator/foreach";import"mnemonist/utils/typed-arrays";var i=e;try{"default"in e&&(i=e.default)}catch(t){}var s=typeof globalThis!=="undefined"?globalThis:typeof self!=="undefined"?self:global;var r={};var a=t,o=i;function FixedDeque(t,e){if(arguments.length<2)throw new Error("mnemonist/fixed-deque: expecting an Array class and a capacity.");if(typeof e!=="number"||e<=0)throw new Error("mnemonist/fixed-deque: `capacity` should be a positive number.");(this||s).ArrayClass=t;(this||s).capacity=e;(this||s).items=new t((this||s).capacity);this.clear()}FixedDeque.prototype.clear=function(){(this||s).start=0;(this||s).size=0};
/**
 * Method used to append a value to the deque.
 *
 * @param  {any}    item - Item to append.
 * @return {number}      - Returns the new size of the deque.
 */FixedDeque.prototype.push=function(t){if((this||s).size===(this||s).capacity)throw new Error("mnemonist/fixed-deque.push: deque capacity ("+(this||s).capacity+") exceeded!");var e=(this||s).start+(this||s).size;e>=(this||s).capacity&&(e-=(this||s).capacity);(this||s).items[e]=t;return++(this||s).size};
/**
 * Method used to prepend a value to the deque.
 *
 * @param  {any}    item - Item to prepend.
 * @return {number}      - Returns the new size of the deque.
 */FixedDeque.prototype.unshift=function(t){if((this||s).size===(this||s).capacity)throw new Error("mnemonist/fixed-deque.unshift: deque capacity ("+(this||s).capacity+") exceeded!");var e=(this||s).start-1;(this||s).start===0&&(e=(this||s).capacity-1);(this||s).items[e]=t;(this||s).start=e;return++(this||s).size};FixedDeque.prototype.pop=function(){if((this||s).size!==0){(this||s).size--;var t=(this||s).start+(this||s).size;t>=(this||s).capacity&&(t-=(this||s).capacity);return(this||s).items[t]}};FixedDeque.prototype.shift=function(){if((this||s).size!==0){var t=(this||s).start;(this||s).size--;(this||s).start++;(this||s).start===(this||s).capacity&&((this||s).start=0);return(this||s).items[t]}};FixedDeque.prototype.peekFirst=function(){if((this||s).size!==0)return(this||s).items[(this||s).start]};FixedDeque.prototype.peekLast=function(){if((this||s).size!==0){var t=(this||s).start+(this||s).size-1;t>=(this||s).capacity&&(t-=(this||s).capacity);return(this||s).items[t]}};
/**
 * Method used to get the desired value of the deque.
 *
 * @param  {number} index
 * @return {any}
 */FixedDeque.prototype.get=function(t){if(!((this||s).size===0||t>=(this||s).capacity)){t=(this||s).start+t;t>=(this||s).capacity&&(t-=(this||s).capacity);return(this||s).items[t]}};
/**
 * Method used to iterate over the deque.
 *
 * @param  {function}  callback - Function to call for each item.
 * @param  {object}    scope    - Optional scope.
 * @return {undefined}
 */FixedDeque.prototype.forEach=function(t,e){e=arguments.length>1?e:this||s;var i=(this||s).capacity,r=(this||s).size,a=(this||s).start,o=0;while(o<r){t.call(e,(this||s).items[a],o,this||s);a++;o++;a===i&&(a=0)}};FixedDeque.prototype.toArray=function(){var t=(this||s).start+(this||s).size;if(t<(this||s).capacity)return(this||s).items.slice((this||s).start,t);var e=new(this||s).ArrayClass((this||s).size),i=(this||s).capacity,r=(this||s).size,a=(this||s).start,o=0;while(o<r){e[o]=(this||s).items[a];a++;o++;a===i&&(a=0)}return e};FixedDeque.prototype.values=function(){var t=(this||s).items,e=(this||s).capacity,i=(this||s).size,r=(this||s).start,a=0;return new o((function(){if(a>=i)return{done:true};var s=t[r];r++;a++;r===e&&(r=0);return{value:s,done:false}}))};FixedDeque.prototype.entries=function(){var t=(this||s).items,e=(this||s).capacity,i=(this||s).size,r=(this||s).start,a=0;return new o((function(){if(a>=i)return{done:true};var s=t[r];r++;r===e&&(r=0);return{value:[a++,s],done:false}}))};typeof Symbol!=="undefined"&&(FixedDeque.prototype[Symbol.iterator]=FixedDeque.prototype.values);FixedDeque.prototype.inspect=function(){var t=this.toArray();t.type=(this||s).ArrayClass.name;t.capacity=(this||s).capacity;Object.defineProperty(t,"constructor",{value:FixedDeque,enumerable:false});return t};typeof Symbol!=="undefined"&&(FixedDeque.prototype[Symbol.for("nodejs.util.inspect.custom")]=FixedDeque.prototype.inspect)
/**
 * Static @.from function taking an arbitrary iterable & converting it into
 * a deque.
 *
 * @param  {Iterable} iterable   - Target iterable.
 * @param  {function} ArrayClass - Array class to use.
 * @param  {number}   capacity   - Desired capacity.
 * @return {FiniteStack}
 */;FixedDeque.from=function(t,e,i){if(arguments.length<3){i=a.guessLength(t);if(typeof i!=="number")throw new Error("mnemonist/fixed-deque.from: could not guess iterable length. Please provide desired capacity as last argument.")}var s=new FixedDeque(e,i);if(a.isArrayLike(t)){var r,o;for(r=0,o=t.length;r<o;r++)s.items[r]=t[r];s.size=o;return s}a.forEach(t,(function(t){s.push(t)}));return s};r=FixedDeque;var n=r;export{n as default};
