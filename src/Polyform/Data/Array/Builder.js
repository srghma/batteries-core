/* global exports, require */
/* jshint -W097 */
"use strict";

export function unsafeCons(a) {
  return function(arr) {
    arr.unshift(a);
    return arr;
  };
}

export function unsafeSnoc(a) {
  return function(arr) {
    arr.push(a);
    return arr;
  };
}
