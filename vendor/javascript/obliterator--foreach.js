// obliterator/foreach@2.0.5 downloaded from https://ga.jspm.io/npm:obliterator@2.0.5/foreach.js

import{e as r}from"obliterator/_/TukZPN2J";var e={};var o=r;var t=o.ARRAY_BUFFER_SUPPORT;var a=o.SYMBOL_SUPPORT;
/**
 * Function able to iterate over almost any iterable JS value.
 *
 * @param  {any}      iterable - Iterable value.
 * @param  {function} callback - Callback function.
 */e=function forEach(r,e){var o,i,f,n,l;if(!r)throw new Error("obliterator/forEach: invalid iterable.");if(typeof e!=="function")throw new Error("obliterator/forEach: expecting a callback.");if(Array.isArray(r)||t&&ArrayBuffer.isView(r)||typeof r==="string"||r.toString()==="[object Arguments]")for(f=0,n=r.length;f<n;f++)e(r[f],f);else if(typeof r.forEach!=="function"){a&&Symbol.iterator in r&&typeof r.next!=="function"&&(r=r[Symbol.iterator]());if(typeof r.next!=="function")for(i in r)r.hasOwnProperty(i)&&e(r[i],i);else{o=r;f=0;while(l=o.next(),l.done!==true){e(l.value,f);f++}}}else r.forEach(e)};var i=e;export{i as default};
