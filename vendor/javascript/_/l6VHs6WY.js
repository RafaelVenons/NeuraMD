import*as r from"obliterator/foreach";import e from"mnemonist/utils/typed-arrays";var t=r;try{"default"in r&&(t=r.default)}catch(r){}var a={};var n=t;var i=e;
/**
 * Function used to determine whether the given object supports array-like
 * random access.
 *
 * @param  {any} target - Target object.
 * @return {boolean}
 */function isArrayLike(r){return Array.isArray(r)||i.isTypedArray(r)}
/**
 * Function used to guess the length of the structure over which we are going
 * to iterate.
 *
 * @param  {any} target - Target object.
 * @return {number|undefined}
 */function guessLength(r){return typeof r.length==="number"?r.length:typeof r.size==="number"?r.size:void 0}
/**
 * Function used to convert an iterable to an array.
 *
 * @param  {any}   target - Iteration target.
 * @return {array}
 */function toArray(r){var e=guessLength(r);var t=typeof e==="number"?new Array(e):[];var a=0;n(r,(function(r){t[a++]=r}));return t}
/**
 * Same as above but returns a supplementary indices array.
 *
 * @param  {any}   target - Iteration target.
 * @return {array}
 */function toArrayWithIndices(r){var e=guessLength(r);var t=typeof e==="number"?i.getPointerArray(e):Array;var a=typeof e==="number"?new Array(e):[];var o=typeof e==="number"?new t(e):[];var y=0;n(r,(function(r){a[y]=r;o[y]=y++}));return[a,o]}a.isArrayLike=isArrayLike;a.guessLength=guessLength;a.toArray=toArray;a.toArrayWithIndices=toArrayWithIndices;export{a as e};
//# sourceMappingURL=l6VHs6WY.js.map
