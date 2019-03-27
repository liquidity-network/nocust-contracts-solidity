pragma solidity ^0.4.24;

library SafeMathLib64 {
  function add(uint64 a, uint64 b) internal pure returns (uint64) {
    uint64 c = a + b;
    require(c >= a, '+');

    return c;
  }
  
  function sub(uint64 a, uint64 b) internal pure returns (uint64) {
    require(b <= a, '-');
    return a - b;
  }
  
  function mul(uint64 a, uint64 b) internal pure returns (uint64) {
    if (a == 0) {
      return 0;
    }

    uint64 c = a * b;
    require(c / a == b, '*');

    return c;
  }
  
  function div(uint64 a, uint64 b) internal pure returns (uint64) {
    require(b > 0, '/');
    return a / b;
  }
  
  function mod(uint64 a, uint64 b) internal pure returns (uint64) {
    require(b > 0, '%');
    return a % b;
  }
}