// graphology-utils/defaults@2.5.2 downloaded from https://ga.jspm.io/npm:graphology-utils@2.5.2/defaults.js

var e={};function isLeaf(e){return!e||"object"!==typeof e||"function"===typeof e||Array.isArray(e)||e instanceof Set||e instanceof Map||e instanceof RegExp||e instanceof Date}function resolveDefaults(e,a){e=e||{};var r={};for(var t in a){var n=e[t];var f=a[t];isLeaf(f)?r[t]=void 0===n?f:n:r[t]=resolveDefaults(n,f)}return r}e=resolveDefaults;var a=e;export{a as default};

