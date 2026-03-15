var r={};
/**
 * When using an unsigned integer array to store pointers, one might want to
 * choose the optimal word size in regards to the actual numbers of pointers
 * to store.
 *
 * This helpers does just that.
 *
 * @param  {number} size - Expected size of the array to map.
 * @return {TypedArray}
 */var t=Math.pow(2,8)-1,n=Math.pow(2,16)-1,a=Math.pow(2,32)-1;var e=Math.pow(2,7)-1,i=Math.pow(2,15)-1,o=Math.pow(2,31)-1;r.getPointerArray=function(r){var e=r-1;if(e<=t)return Uint8Array;if(e<=n)return Uint16Array;if(e<=a)return Uint32Array;throw new Error("mnemonist: Pointer Array of size > 4294967295 is not supported.")};r.getSignedPointerArray=function(r){var t=r-1;return t<=e?Int8Array:t<=i?Int16Array:t<=o?Int32Array:Float64Array};
/**
 * Function returning the minimal type able to represent the given number.
 *
 * @param  {number} value - Value to test.
 * @return {TypedArrayClass}
 */r.getNumberType=function(r){return r===(r|0)?Math.sign(r)===-1?r<=127&&r>=-128?Int8Array:r<=32767&&r>=-32768?Int16Array:Int32Array:r<=255?Uint8Array:r<=65535?Uint16Array:Uint32Array:Float64Array};
/**
 * Function returning the minimal type able to represent the given array
 * of JavaScript numbers.
 *
 * @param  {array}    array  - Array to represent.
 * @param  {function} getter - Optional getter.
 * @return {TypedArrayClass}
 */var y={Uint8Array:1,Int8Array:2,Uint16Array:3,Int16Array:4,Uint32Array:5,Int32Array:6,Float32Array:7,Float64Array:8};r.getMinimalRepresentation=function(t,n){var a,e,i,o,A,u=null,f=0;for(o=0,A=t.length;o<A;o++){i=n?n(t[o]):t[o];e=r.getNumberType(i);a=y[e.name];if(a>f){f=a;u=e}}return u};
/**
 * Function returning whether the given value is a typed array.
 *
 * @param  {any} value - Value to test.
 * @return {boolean}
 */r.isTypedArray=function(r){return typeof ArrayBuffer!=="undefined"&&ArrayBuffer.isView(r)};
/**
 * Function used to concat byte arrays.
 *
 * @param  {...ByteArray}
 * @return {ByteArray}
 */r.concat=function(){var r,t,n,a=0;for(r=0,n=arguments.length;r<n;r++)a+=arguments[r].length;var e=new arguments[0].constructor(a);for(r=0,t=0;r<n;r++){e.set(arguments[r],t);t+=arguments[r].length}return e};
/**
 * Function used to initialize a byte array of indices.
 *
 * @param  {number}    length - Length of target.
 * @return {ByteArray}
 */r.indices=function(t){var n=r.getPointerArray(t);var a=new n(t);for(var e=0;e<t;e++)a[e]=e;return a};const A=r.getPointerArray,u=r.getSignedPointerArray,f=r.getNumberType,g=r.getMinimalRepresentation,p=r.isTypedArray,c=r.concat,s=r.indices;export{c as concat,r as default,g as getMinimalRepresentation,f as getNumberType,A as getPointerArray,u as getSignedPointerArray,s as indices,p as isTypedArray};
//# sourceMappingURL=typed-arrays.js.map
