// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract DbgEntry {
    uint public a;
    
    constructor() {}

    function test() private {
        uint b = a + 1;
        a = b;
    }
    
}
