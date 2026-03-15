// obliterator/iterator@2.0.5 downloaded from https://ga.jspm.io/npm:obliterator@2.0.5/iterator.js

var t=typeof globalThis!=="undefined"?globalThis:typeof self!=="undefined"?self:global;var e={};
/**
 * Iterator class.
 *
 * @constructor
 * @param {function} next - Next function.
 */function Iterator(e){if(typeof e!=="function")throw new Error("obliterator/iterator: expecting a function!");(this||t).next=e}typeof Symbol!=="undefined"&&(Iterator.prototype[Symbol.iterator]=function(){return this||t})
/**
 * Returning an iterator of the given values.
 *
 * @param  {any...} values - Values.
 * @return {Iterator}
 */;Iterator.of=function(){var t=arguments,e=t.length,r=0;return new Iterator((function(){return r>=e?{done:true}:{done:false,value:t[r++]}}))};Iterator.empty=function(){var t=new Iterator((function(){return{done:true}}));return t};
/**
 * Returning an iterator over the given indexed sequence.
 *
 * @param  {string|Array} sequence - Target sequence.
 * @return {Iterator}
 */Iterator.fromSequence=function(t){var e=0,r=t.length;return new Iterator((function(){return e>=r?{done:true}:{done:false,value:t[e++]}}))};
/**
 * Returning whether the given value is an iterator.
 *
 * @param  {any} value - Value.
 * @return {boolean}
 */Iterator.is=function(t){return t instanceof Iterator||typeof t==="object"&&t!==null&&typeof t.next==="function"};e=Iterator;var r=e;export{r as default};

