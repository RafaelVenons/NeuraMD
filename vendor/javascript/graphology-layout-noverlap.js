// graphology-layout-noverlap@0.4.2 downloaded from https://ga.jspm.io/npm:graphology-layout-noverlap@0.4.2/index.js

import*as r from"graphology-utils/is-graph";import{e as a,_ as t}from"graphology-layout-noverlap/_/a72dd12e";var o={};var e=0,n=1,i=2;var v=3;function hashPair(r,a){return r+"§"+a}function jitter(){return.01*(.5-Math.random())}
/**
 * Function used to perform a single interation of the algorithm.
 *
 * @param  {object}       options    - Layout options.
 * @param  {Float32Array} NodeMatrix - Node data.
 * @return {object}                  - Some metadata.
 */o=function iterate(r,a){var t=r.margin;var o=r.ratio;var s=r.expansion;var u=r.gridSize;var f=r.speed;var h,l,g,y,p,d;var c=true;var m=a.length;var w=m/v|0;var M=new Float32Array(w);var b=new Float32Array(w);var x=Infinity;var I=Infinity;var S=-Infinity;var j=-Infinity;for(h=0;h<m;h+=v){g=a[h+e];y=a[h+n];d=a[h+i]*o+t;x=Math.min(x,g-d);S=Math.max(S,g+d);I=Math.min(I,y-d);j=Math.max(j,y+d)}var L=S-x;var A=j-I;var E=(x+S)/2;var R=(I+j)/2;x=E-s*L/2;S=E+s*L/2;I=R-s*A/2;j=R+s*A/2;var C,F=new Array(u*u),P=F.length;for(C=0;C<P;C++)F[C]=[];var _,q,z,B;var O,T,k,D;var G,H;for(h=0;h<m;h+=v){g=a[h+e];y=a[h+n];d=a[h+i]*o+t;_=g-d;q=g+d;z=y-d;B=y+d;O=Math.floor(u*(_-x)/(S-x));T=Math.floor(u*(q-x)/(S-x));k=Math.floor(u*(z-I)/(j-I));D=Math.floor(u*(B-I)/(j-I));for(G=O;G<=T;G++)for(H=k;H<=D;H++)F[G*u+H].push(h)}var J;var K=new Set;var N,Q,U,V,W,X,Y,Z,$;var rr,ar,tr,or;for(C=0;C<P;C++){J=F[C];for(h=0,p=J.length;h<p;h++){N=J[h];U=a[N+e];W=a[N+n];Y=a[N+i];for(l=h+1;l<p;l++){Q=J[l];$=hashPair(N,Q);if(!(P>1&&K.has($))){P>1&&K.add($);V=a[Q+e];X=a[Q+n];Z=a[Q+i];rr=V-U;ar=X-W;tr=Math.sqrt(rr*rr+ar*ar);or=tr<Y*o+t+(Z*o+t);if(or){c=false;Q=Q/v|0;if(tr>0){M[Q]+=rr/tr*(1+Y);b[Q]+=ar/tr*(1+Y)}else{M[Q]+=L*jitter();b[Q]+=A*jitter()}}}}}}for(h=0,l=0;h<m;h+=v,l++){a[h+e]+=.1*M[l]*f;a[h+n]+=.1*b[l]*f}return{converged:c}};var s=o;var u="default"in r?r.default:r;var f={};var h=u;var l=s;var g=a;var y=t;var p=500;
/**
 * Asbtract function used to run a certain number of iterations.
 *
 * @param  {boolean}       assign       - Whether to assign positions.
 * @param  {Graph}         graph        - Target graph.
 * @param  {object|number} params       - If number, params.maxIterations, else:
 * @param  {number}          maxIterations - Maximum number of iterations.
 * @param  {object}          [settings] - Settings.
 * @return {object|undefined}
 */function abstractSynchronousLayout(r,a,t){if(!h(a))throw new Error("graphology-layout-noverlap: the given graph is not a valid graphology instance.");t="number"===typeof t?{maxIterations:t}:t||{};var o=t.maxIterations||p;if("number"!==typeof o||o<=0)throw new Error("graphology-layout-force: you should provide a positive number of maximum iterations.");var e=Object.assign({},y,t.settings),n=g.validateSettings(e);if(n)throw new Error("graphology-layout-noverlap: "+n.message);var i,v=g.graphToByteArray(a,t.inputReducer),s=false;for(i=0;i<o&&!s;i++)s=l(e,v).converged;if(!r)return g.collectLayoutChanges(a,v,t.outputReducer);g.assignLayoutChanges(a,v,t.outputReducer)}var d=abstractSynchronousLayout.bind(null,false);d.assign=abstractSynchronousLayout.bind(null,true);f=d;var c=f;export{c as default};
