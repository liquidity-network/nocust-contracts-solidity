pragma solidity ^0.4.24;

import "./ERC20.sol";
import "./BimodalLib.sol";
import "./BimodalProxy.sol";
import "./DepositLib.sol";
import "./SafeMath/SafeMathLib256.sol";

contract DepositProxy is BimodalProxy {
  using SafeMathLib256 for uint256;

  function()
    public
    payable
  {}

  function deposit(
    ERC20 token,
    address beneficiary,
    uint256 amount
  )
    public
    payable
    onlyWhenContractUnpunished()
  {
    DepositLib.deposit(
      ledger,
      token,
      beneficiary,
      amount);
  }
}
