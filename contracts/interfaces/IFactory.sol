// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IFactory {
  event poolCreated(address indexed tokenA, address indexed tokenB, address pool, uint);

  function getpool(address tokenA, address tokenB) external view returns (address pool);
  function allpools(uint) external view returns (address pool);
  function allpoolsLength() external view returns (uint);

  function feeTo() external view returns (address);
  function feeToSetter() external view returns (address);

  function createpool(address tokenA, address tokenB) external returns (address pool);
}