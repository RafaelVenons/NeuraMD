// pandemonium/shuffle-in-place@2.4.1 downloaded from https://ga.jspm.io/npm:pandemonium@2.4.1/shuffle-in-place.js

var e={};function r(a){return function(e,n){return e+Math.floor(a()*(n-e+1))}};
/**
 * Creating a function returning the given array shuffled.
 *
 * @param  {function} rng - The RNG to use.
 * @return {function}     - The created function.
 */function createShuffleInPlace(a){var e=r(a);
/**
   * Function returning the shuffled array.
   *
   * @param  {array}  sequence - Target sequence.
   * @return {array}           - The shuffled sequence.
   */return function(a){var r=a.length,n=r-1;var t=-1;while(++t<r){var f=e(t,n),c=a[f];a[f]=a[t];a[t]=c}}}var n=createShuffleInPlace(Math.random);n.createShuffleInPlace=createShuffleInPlace;e=n;var t=e;export{t as default};
