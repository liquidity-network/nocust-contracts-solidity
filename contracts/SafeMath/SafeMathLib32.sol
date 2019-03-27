pragma solidity ^0.4.24;

library SafeMathLib32 {
  function add(uint32 a, uint32 b) internal pure returns (uint32) {
    uint32 c = a + b;
    require(c >= a, '+');

    return c;
  }

  function sub(uint32 a, uint32 b) internal pure returns (uint32) {
    require(b <= a, '-');
    return a - b;
  }

  function mul(uint32 a, uint32 b) internal pure returns (uint32) {
    if (a == 0) {
      return 0;
    }

    uint32 c = a * b;
    require(c / a == b, '*');

    return c;
  }

  function div(uint32 a, uint32 b) internal pure returns (uint32) {
    require(b > 0, '/');
    return a / b;
  }

  function mod(uint32 a, uint32 b) internal pure returns (uint32) {
    require(b > 0, '%');
    return a % b;
  }
}